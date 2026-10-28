// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The tool registry: system tools (spec section 6.2) now, Keel Actions
//! from `keel-mcp` (section 9) later, under one set of rules:
//!
//! - every call's arguments are validated against the tool's JSON Schema
//!   before anything runs (section 6.1);
//! - outputs are validated against `outputSchema` when a tool has one
//!   (section 9.3);
//! - destructive and outbound tools always get a confirmation card
//!   (section 4, step 5), read-only tools never do.
//!
//! Canonical names keep their dots and app prefixes
//! (`timer.set`, `org.shipwright.notes/notes.create`); the model sees a
//! sanitised name (`^[a-zA-Z0-9_-]{1,64}$`, what OpenAI-compatible servers
//! accept) that the registry maps back.

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use serde::Serialize;
use serde_json::Value;

use crate::llm::{ToolCall, ToolDef};
use crate::schema::Validator;

/// When a call needs the user's explicit yes.
#[derive(Clone, Copy)]
pub enum Confirm {
    Never,
    Always,
    /// Decided per call from the (restored) arguments.
    When(fn(&Value) -> bool),
}

impl std::fmt::Debug for Confirm {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Confirm::Never => "Never",
            Confirm::Always => "Always",
            Confirm::When(_) => "When(..)",
        })
    }
}

#[derive(Debug, Clone)]
pub struct ToolSpec {
    /// Canonical name.
    pub name: String,
    /// Short human title for cards ("Send message").
    pub title: String,
    pub description: String,
    pub input: Validator,
    pub output: Option<Validator>,
    pub confirm: Confirm,
    pub read_only: bool,
    pub destructive: bool,
    /// Reaches the network or another person (send, call, share).
    pub open_world: bool,
    /// Routing domain for two-stage Jev routing (section 9.5).
    pub domain: String,
}

impl ToolSpec {
    pub fn needs_confirmation(&self, args: &Value) -> bool {
        if self.read_only {
            return false;
        }
        if self.destructive || self.open_world {
            return true;
        }
        match self.confirm {
            Confirm::Never => false,
            Confirm::Always => true,
            Confirm::When(f) => f(args),
        }
    }
}

/// What a tool returns.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ToolOutput {
    /// One short sentence for the user ("Timer set for 5 minutes.").
    pub summary: String,
    /// Structured result for the model and `outputSchema`.
    pub data: Value,
    /// For the person only (a sensitive Keel Action result): shown on a
    /// card, never sent to a model.
    #[serde(skip)]
    pub private: bool,
    /// Third-party content (a web page, someone's message: a Keel Action
    /// declared `untrusted`). It reaches the model only as quoted data in
    /// a tool result, never as instructions, and after it every action
    /// that changes something needs the person's yes.
    #[serde(skip)]
    pub untrusted: bool,
    /// `summary` answers the question by itself (a forecast in words, not
    /// "Weather for Dublin"): one such lookup needs no model round after.
    #[serde(skip)]
    pub answers: bool,
}

/// What a tool says before a call runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Precheck {
    Proceed,
    /// Needs the person's yes, with this description (a whole plan).
    Confirm(String),
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ToolError {
    #[error("{0}")]
    Unavailable(String),
    #[error("{0}")]
    Failed(String),
    #[error("invalid output: {0}")]
    BadOutput(String),
    /// The call cannot run as given; the message goes back to the model.
    #[error("{0}")]
    Invalid(String),
}

impl From<crate::adapters::AdapterError> for ToolError {
    fn from(e: crate::adapters::AdapterError) -> Self {
        match e {
            crate::adapters::AdapterError::Unavailable(_) => ToolError::Unavailable(e.to_string()),
            crate::adapters::AdapterError::Failed(m) => ToolError::Failed(m),
        }
    }
}

/// Runs calls for one or more tools.
#[async_trait]
pub trait ToolExecutor: Send + Sync {
    /// Checks a validated call before anything runs (a plan's steps).
    async fn precheck(&self, _tool: &str, _args: &Value) -> Result<Precheck, ToolError> {
        Ok(Precheck::Proceed)
    }
    async fn call(&self, tool: &str, args: &Value) -> Result<ToolOutput, ToolError>;
}

#[derive(Clone)]
pub struct Entry {
    pub spec: ToolSpec,
    pub model_name: String,
    pub available: bool,
    exec: Arc<dyn ToolExecutor>,
}

impl std::fmt::Debug for Entry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Entry")
            .field("name", &self.spec.name)
            .field("model_name", &self.model_name)
            .field("available", &self.available)
            .finish_non_exhaustive()
    }
}

impl Entry {
    pub async fn precheck(&self, args: &Value) -> Result<Precheck, ToolError> {
        self.exec.precheck(&self.spec.name, args).await
    }

    /// Executes and validates the output against `outputSchema`.
    pub async fn run(&self, args: &Value) -> Result<ToolOutput, ToolError> {
        let out = self.exec.call(&self.spec.name, args).await?;
        // A private result carries no data here: its server checked it
        // against the schema before withholding it.
        if let (Some(v), false) = (&self.spec.output, out.private) {
            let errs = v.validate(&out.data);
            if let Some(first) = errs.first() {
                return Err(ToolError::BadOutput(first.to_string()));
            }
        }
        Ok(out)
    }
}

/// A rejected call, phrased for the model to fix.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rejection(pub String);

#[derive(Default, Clone)]
pub struct Registry {
    entries: Vec<Entry>,
    by_model: HashMap<String, usize>,
    by_name: HashMap<String, usize>,
}

/// A model-safe tool name: ASCII letters, digits, `_` and `-`, at most 64.
pub fn model_safe(name: &str) -> String {
    let s: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    s.chars().take(64).collect()
}

/// A tool's input schema as the model is given it: `$ref`s inlined and
/// `$defs` gone, without `pattern`, `format` and `x-` keys. Providers check
/// the model's arguments against the schema themselves (Groq answers a
/// near miss with `tool_use_failed` and the turn is lost); pilotd checks
/// them against the full schema and gives the model one correction, so a
/// pattern is said in words instead: an entity reference's description
/// says it is a `keel://` reference from a find tool.
pub fn model_schema(schema: &Value) -> Value {
    fn walk(v: &Value, defs: &serde_json::Map<String, Value>, depth: u8) -> Value {
        match v {
            Value::Object(o) => {
                if let Some(r) = o.get("$ref").and_then(Value::as_str) {
                    let name = r.trim_start_matches("#/$defs/");
                    if let (Some(d), true) = (defs.get(name), depth < 8) {
                        let mut inlined = walk(d, defs, depth + 1);
                        if let (Some(m), Some(desc)) =
                            (inlined.as_object_mut(), o.get("description"))
                        {
                            m.insert("description".into(), desc.clone());
                        }
                        return inlined;
                    }
                }
                let entity = o
                    .get("x-keel-entity")
                    .and_then(Value::as_str)
                    .map(str::to_owned);
                let mut out = serde_json::Map::new();
                for (k, val) in o {
                    if k == "$defs"
                        || k == "$ref"
                        || k == "pattern"
                        || k == "format"
                        || k.starts_with("x-")
                    {
                        continue;
                    }
                    out.insert(k.clone(), walk(val, defs, depth));
                }
                if let Some(e) = entity {
                    let said = format!(
                        "A {e} reference, keel://{e}/<id>, exactly as a find tool returned it."
                    );
                    let desc = out
                        .get("description")
                        .and_then(Value::as_str)
                        .map_or_else(|| said.clone(), |d| format!("{d} {said}"));
                    out.insert("description".into(), Value::String(desc));
                }
                Value::Object(out)
            }
            Value::Array(a) => Value::Array(a.iter().map(|x| walk(x, defs, depth)).collect()),
            other => other.clone(),
        }
    }
    let defs = schema
        .get("$defs")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    walk(schema, &defs, 0)
}

impl Registry {
    pub fn new() -> Registry {
        Registry::default()
    }

    /// Adds a tool. A clashing sanitised name gets a numeric suffix; a
    /// clashing canonical name replaces the old entry.
    pub fn add(&mut self, spec: ToolSpec, available: bool, exec: Arc<dyn ToolExecutor>) {
        if let Some(&i) = self.by_name.get(&spec.name) {
            let model_name = self.entries[i].model_name.clone();
            self.entries[i] = Entry {
                spec,
                model_name,
                available,
                exec,
            };
            return;
        }
        let base = model_safe(&spec.name);
        let mut model_name = base.clone();
        let mut n = 2;
        while self.by_model.contains_key(&model_name) {
            let suffix = format!("_{n}");
            model_name = format!("{}{suffix}", &base[..base.len().min(64 - suffix.len())]);
            n += 1;
        }
        let i = self.entries.len();
        self.by_model.insert(model_name.clone(), i);
        self.by_name.insert(spec.name.clone(), i);
        self.entries.push(Entry {
            spec,
            model_name,
            available,
            exec,
        });
    }

    /// Whether `name` is a tool's model-facing name.
    pub fn knows(&self, name: &str) -> bool {
        self.by_model.contains_key(name)
    }

    pub fn get(&self, name: &str) -> Option<&Entry> {
        self.by_name.get(name).map(|&i| &self.entries[i])
    }

    pub fn entries(&self) -> impl Iterator<Item = &Entry> {
        self.entries.iter()
    }

    /// One entry as the model sees it.
    pub fn def(&self, e: &Entry) -> ToolDef {
        ToolDef {
            name: e.model_name.clone(),
            description: e.spec.description.clone(),
            parameters: e.spec.input.schema().clone(),
        }
    }

    /// Tool definitions for the model: available tools, optionally only
    /// those in `domains`.
    pub fn defs(&self, domains: Option<&[String]>) -> Vec<ToolDef> {
        self.entries
            .iter()
            .filter(|e| e.available)
            .filter(|e| domains.is_none_or(|d| d.contains(&e.spec.domain)))
            .map(|e| ToolDef {
                name: e.model_name.clone(),
                description: e.spec.description.clone(),
                parameters: model_schema(e.spec.input.schema()),
            })
            .collect()
    }

    /// Resolves and validates a model's call. The error text goes back to
    /// the model so it can correct itself once.
    pub fn check(&self, call: &ToolCall) -> Result<(&Entry, Value), Rejection> {
        let Some(&i) = self.by_model.get(&call.name) else {
            return Err(Rejection(format!("unknown tool {}", call.name)));
        };
        let entry = &self.entries[i];
        if !entry.available {
            return Err(Rejection(format!("tool {} is not available", call.name)));
        }
        let args: Value = if call.arguments.trim().is_empty() {
            Value::Object(serde_json::Map::new())
        } else {
            serde_json::from_str(&call.arguments)
                .map_err(|e| Rejection(format!("arguments are not valid JSON: {e}")))?
        };
        let errs = entry.spec.input.validate(&args);
        if !errs.is_empty() {
            let msg: Vec<String> = errs.iter().map(ToString::to_string).collect();
            return Err(Rejection(format!(
                "arguments for {} do not match its schema: {}",
                call.name,
                msg.join("; ")
            )));
        }
        Ok((entry, args))
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use serde_json::json;

    struct Echo;

    #[async_trait]
    impl ToolExecutor for Echo {
        async fn call(&self, tool: &str, args: &Value) -> Result<ToolOutput, ToolError> {
            Ok(ToolOutput {
                summary: tool.to_owned(),
                data: args.clone(),
                private: false,
                untrusted: false,
                answers: false,
            })
        }
    }

    fn spec(name: &str, confirm: Confirm) -> ToolSpec {
        ToolSpec {
            name: name.into(),
            title: name.into(),
            description: "d".into(),
            input: Validator::new(
                json!({"type": "object", "properties": {"n": {"type": "integer"}},
                                         "required": ["n"], "additionalProperties": false}),
            )
            .unwrap(),
            output: Some(Validator::new(json!({"type": "object", "required": ["n"]})).unwrap()),
            confirm,
            read_only: false,
            destructive: false,
            open_world: false,
            domain: "system".into(),
        }
    }

    #[tokio::test]
    async fn names_validation_and_confirmation() {
        let mut r = Registry::new();
        r.add(
            spec("org.shipwright.notes/notes.create", Confirm::Never),
            true,
            Arc::new(Echo),
        );
        r.add(
            spec("org_shipwright_notes_notes_create", Confirm::Always),
            true,
            Arc::new(Echo),
        );
        r.add(spec("hidden.tool", Confirm::Never), false, Arc::new(Echo));
        let defs = r.defs(None);
        let names: Vec<&str> = defs.iter().map(|d| d.name.as_str()).collect();
        assert_eq!(
            names,
            [
                "org_shipwright_notes_notes_create",
                "org_shipwright_notes_notes_create_2"
            ]
        );

        let call = |name: &str, args: &str| ToolCall {
            id: "1".into(),
            name: name.into(),
            arguments: args.into(),
        };
        let (e, args) = r
            .check(&call("org_shipwright_notes_notes_create", r#"{"n": 1}"#))
            .unwrap();
        assert_eq!(e.spec.name, "org.shipwright.notes/notes.create");
        assert!(!e.spec.needs_confirmation(&args));
        assert_eq!(e.run(&args).await.unwrap().data, json!({"n": 1}));
        let (e2, _) = r
            .check(&call("org_shipwright_notes_notes_create_2", r#"{"n": 1}"#))
            .unwrap();
        assert!(e2.spec.needs_confirmation(&json!({})));

        let bad = r
            .check(&call(
                "org_shipwright_notes_notes_create",
                r#"{"n": "x", "m": 1}"#,
            ))
            .unwrap_err();
        assert!(bad.0.contains("/n: expected integer"), "{}", bad.0);
        assert!(bad.0.contains("/m: unexpected property"), "{}", bad.0);
        assert!(r
            .check(&call("org_shipwright_notes_notes_create", "{nope"))
            .is_err());
        assert!(r.check(&call("nope", "{}")).is_err());
        assert!(r.check(&call("hidden_tool", r#"{"n": 1}"#)).is_err());
        // Output schema enforced.
        assert!(matches!(
            e.run(&json!({})).await,
            Err(ToolError::BadOutput(_))
        ));
    }

    #[test]
    fn hints_override_policy() {
        let mut s = spec("x", Confirm::Never);
        s.destructive = true;
        assert!(s.needs_confirmation(&json!({})));
        s.destructive = false;
        s.open_world = true;
        assert!(s.needs_confirmation(&json!({})));
        s.read_only = true;
        assert!(!s.needs_confirmation(&json!({})));
        let s = spec("y", Confirm::When(|a| a["n"] == 1));
        assert!(s.needs_confirmation(&json!({"n": 1})));
        assert!(!s.needs_confirmation(&json!({"n": 2})));
    }

    #[test]
    fn model_schema_inlines_refs_and_drops_patterns() {
        let s = serde_json::json!({"$defs": {"org.shipwright.reef.app": {"format": "uri", "maxLength": 287,
            "pattern": "^keel://org\\.shipwright\\.reef/app/[^/?#\\s]{1,256}$", "type": "string",
            "x-keel-entity": "org.shipwright.reef/app"}}, "additionalProperties": false,
            "properties": {"app": {"$ref": "#/$defs/org.shipwright.reef.app"}}, "required": ["app"], "type": "object"});
        let m = model_schema(&s);
        assert!(m.get("$defs").is_none());
        let app = &m["properties"]["app"];
        assert_eq!(app["type"], "string");
        assert_eq!(app["maxLength"], 287);
        assert!(
            app.get("pattern").is_none()
                && app.get("format").is_none()
                && app.get("x-keel-entity").is_none()
        );
        assert!(app["description"]
            .as_str()
            .unwrap()
            .contains("keel://org.shipwright.reef/app/<id>"));
        assert_eq!(m["required"], serde_json::json!(["app"]));
    }
}
