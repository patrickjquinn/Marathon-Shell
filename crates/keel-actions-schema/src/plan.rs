// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Plans (`docs/specs/pilot.md` 9.7): several tool calls run in order,
//! where a later step may use an earlier step's output.
//!
//! ```json
//! { "steps": [
//!     { "tool": "org.example.notes/note.find", "arguments": { "query": "yesterday" } },
//!     { "tool": "org.example.mail/mail.compose",
//!       "arguments": { "attach": { "$step": 0, "path": "/items/0/uri" }, "to": "anna@example.org" } }
//! ] }
//! ```
//!
//! A reference `{ "$step": n, "path": "<json pointer>" }` stands for the
//! value at `path` in step `n`'s structured output. [`validate_plan`]
//! checks everything that can be checked before the first step runs: the
//! tools exist; references point backwards, into a declared output, to a
//! value whose schema fits the parameter (same type; for entity
//! references, the same `x-keel-entity`); and the literal arguments, with
//! each reference stood in for by an example of its target, validate
//! against the tool's input schema. [`resolve_arguments`] substitutes the
//! real outputs when the plan runs.

use std::fmt;

use std::fmt::Write as _;

use serde_json::{Map, Value};

use crate::example::example;
use crate::meta_key;
use crate::validate::{resolve, type_of, validate};

/// At most this many steps in a plan.
pub const MAX_STEPS: usize = 16;

/// A problem that stops the plan from running.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlanError {
    /// The step (0-based), or `None` for the plan as a whole.
    pub step: Option<usize>,
    pub message: String,
}

impl fmt::Display for PlanError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.step {
            Some(s) => write!(f, "step {s}: {}", self.message),
            None => f.write_str(&self.message),
        }
    }
}

/// What the person has to be told before the plan runs.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PlanSummary {
    pub tools: Vec<String>,
    /// Steps that are destructive, open-world (outbound) or ask to confirm.
    pub needs_confirmation: Vec<usize>,
}

/// A parsed step.
#[derive(Clone, Debug, PartialEq)]
pub struct PlanStep {
    pub tool: String,
    pub arguments: Value,
}

/// The steps of a plan value, or why it is not one.
pub fn parse_plan(plan: &Value) -> Result<Vec<PlanStep>, PlanError> {
    let whole = |m: &str| PlanError {
        step: None,
        message: m.to_owned(),
    };
    let steps = plan
        .get("steps")
        .and_then(Value::as_array)
        .ok_or_else(|| whole("a plan is { \"steps\": [ { \"tool\", \"arguments\" }, ... ] }"))?;
    if steps.is_empty() || steps.len() > MAX_STEPS {
        return Err(whole(&format!("a plan has 1 to {MAX_STEPS} steps")));
    }
    steps
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let tool = s
                .get("tool")
                .and_then(Value::as_str)
                .ok_or_else(|| PlanError {
                    step: Some(i),
                    message: "no tool".into(),
                })?;
            let arguments = s
                .get("arguments")
                .cloned()
                .unwrap_or(Value::Object(Map::new()));
            if !arguments.is_object() {
                return Err(PlanError {
                    step: Some(i),
                    message: "arguments must be an object".into(),
                });
            }
            Ok(PlanStep {
                tool: tool.to_owned(),
                arguments,
            })
        })
        .collect()
}

/// A reference's step and path, if `value` is one.
pub fn as_reference(value: &Value) -> Option<(u64, &str)> {
    let map = value.as_object()?;
    if map.len() != 2 {
        return None;
    }
    Some((map.get("$step")?.as_u64()?, map.get("path")?.as_str()?))
}

/// The schema at `pointer` inside an object schema (through `properties`
/// and `items`), with its root for `$ref`s.
fn schema_at<'a>(schema: &'a Value, root: &'a Value, pointer: &str) -> Option<&'a Value> {
    let mut current = resolve(schema, root).ok()?;
    if pointer.is_empty() || pointer == "/" {
        return Some(current);
    }
    for raw in pointer.strip_prefix('/')?.split('/') {
        let token = raw.replace("~1", "/").replace("~0", "~");
        current = match current.get("type").and_then(Value::as_str) {
            Some("object") => current.get("properties")?.get(&token)?,
            Some("array") if token.parse::<usize>().is_ok() => current.get("items")?,
            _ => return None,
        };
        current = resolve(current, root).ok()?;
    }
    Some(current)
}

fn schema_type(schema: &Value) -> Option<&str> {
    schema.get("type").and_then(Value::as_str)
}

/// Can a value of `source` stand where `target` is expected?
fn compatible(source: &Value, target: &Value) -> Result<(), String> {
    let source_entity = source.get("x-keel-entity").and_then(Value::as_str);
    if let Some(wanted) = target.get("x-keel-entity").and_then(Value::as_str) {
        return match source_entity {
            Some(e) if e == wanted => Ok(()),
            Some(e) => Err(format!("a reference to {e} where {wanted} is expected")),
            None => Err(format!(
                "a plain {} where a reference to {wanted} is expected",
                schema_type(source).unwrap_or("value")
            )),
        };
    }
    let (s, t) = (schema_type(source), schema_type(target));
    match (s, t) {
        (Some(s), Some(t)) if s == t || (s == "integer" && t == "number") => Ok(()),
        (_, None) => Ok(()),
        (s, Some(t)) => Err(format!(
            "a {} where a {t} is expected",
            s.unwrap_or("value")
        )),
    }
}

/// Walks `arguments`, calling `f(pointer, step, path)` for each reference.
fn references(value: &Value, pointer: &mut String, f: &mut dyn FnMut(&str, u64, &str)) {
    if let Some((step, path)) = as_reference(value) {
        f(pointer, step, path);
        return;
    }
    match value {
        Value::Object(map) => {
            for (k, v) in map {
                let len = pointer.len();
                pointer.push('/');
                pointer.push_str(&crate::validate::escape_pointer(k));
                references(v, pointer, f);
                pointer.truncate(len);
            }
        }
        Value::Array(items) => {
            for (i, v) in items.iter().enumerate() {
                let len = pointer.len();
                let _ = write!(pointer, "/{i}");
                references(v, pointer, f);
                pointer.truncate(len);
            }
        }
        _ => {}
    }
}

/// Replaces every reference in `arguments` with `with(step, path, pointer)`.
fn substitute(
    value: &Value,
    pointer: &mut String,
    with: &mut dyn FnMut(u64, &str, &str) -> Result<Value, String>,
) -> Result<Value, String> {
    if let Some((step, path)) = as_reference(value) {
        return with(step, path, pointer);
    }
    Ok(match value {
        Value::Object(map) => {
            let mut out = Map::new();
            for (k, v) in map {
                let len = pointer.len();
                pointer.push('/');
                pointer.push_str(&crate::validate::escape_pointer(k));
                out.insert(k.clone(), substitute(v, pointer, with)?);
                pointer.truncate(len);
            }
            Value::Object(out)
        }
        Value::Array(items) => {
            let mut out = Vec::new();
            for (i, v) in items.iter().enumerate() {
                let len = pointer.len();
                let _ = write!(pointer, "/{i}");
                out.push(substitute(v, pointer, with)?);
                pointer.truncate(len);
            }
            Value::Array(out)
        }
        other => other.clone(),
    })
}

fn flag(tool: &Value, hint: &str) -> bool {
    tool.get("annotations")
        .and_then(|a| a.get(hint))
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

/// Does this tool need the person's go-ahead (destructive, outbound, or
/// declared `confirm`)?
pub fn needs_confirmation(tool: &Value) -> bool {
    let read_only = flag(tool, "readOnlyHint");
    (!read_only && flag(tool, "destructiveHint"))
        || flag(tool, "openWorldHint")
        || tool
            .get("_meta")
            .and_then(|m| m.get(meta_key("confirm")))
            .and_then(Value::as_bool)
            .unwrap_or(false)
}

/// Validates a plan against the tools `lookup` knows (by full name).
pub fn validate_plan<'a>(
    plan: &Value,
    lookup: &dyn Fn(&str) -> Option<&'a Value>,
) -> Result<PlanSummary, Vec<PlanError>> {
    let steps = parse_plan(plan).map_err(|e| vec![e])?;
    let mut errors = Vec::new();
    let mut summary = PlanSummary::default();
    let tools: Vec<Option<&Value>> = steps.iter().map(|s| lookup(&s.tool)).collect();
    for (i, step) in steps.iter().enumerate() {
        let mut error = |message: String| {
            errors.push(PlanError {
                step: Some(i),
                message,
            });
        };
        summary.tools.push(step.tool.clone());
        let Some(tool) = tools[i] else {
            error(format!("no tool named {}", step.tool));
            continue;
        };
        if needs_confirmation(tool) {
            summary.needs_confirmation.push(i);
        }
        let input = tool.get("inputSchema").cloned().unwrap_or(Value::Null);
        let mut reference_errors = Vec::new();
        references(
            &step.arguments,
            &mut String::new(),
            &mut |at, from, path| {
                let target = schema_at(&input, &input, at);
                let Some(target) = target else {
                    reference_errors.push(format!("{at}: the tool has no parameter there"));
                    return;
                };
                let from = usize::try_from(from).unwrap_or(usize::MAX);
                if from >= i {
                    reference_errors.push(format!(
                        "{at}: refers to step {from}, which does not run before this one"
                    ));
                    return;
                }
                let Some(output) = tools[from].and_then(|t| t.get("outputSchema")) else {
                    reference_errors.push(format!("{at}: step {from} has no structured output"));
                    return;
                };
                match schema_at(output, output, path) {
                    None => reference_errors
                        .push(format!("{at}: step {from}'s output has nothing at {path}")),
                    Some(source) => {
                        if let Err(e) = compatible(source, target) {
                            reference_errors.push(format!("{at}: {e}"));
                        }
                    }
                }
            },
        );
        for e in reference_errors {
            error(e);
        }
        // Literal arguments, with references replaced by examples of what
        // they stand for.
        let stood_in = substitute(&step.arguments, &mut String::new(), &mut |_, _, at| {
            Ok(schema_at(&input, &input, at).map_or(Value::Null, |target| {
                let mut s = target.clone();
                if let (Value::Object(map), Some(defs)) = (&mut s, input.get("$defs")) {
                    map.insert("$defs".into(), defs.clone());
                }
                example(&s).0
            }))
        });
        if let Ok(value) = stood_in {
            if let Err(invalid) = validate(&input, &value) {
                error(invalid.to_string());
            }
        }
    }
    if errors.is_empty() {
        Ok(summary)
    } else {
        Err(errors)
    }
}

/// The value at a JSON pointer.
pub fn pointer<'a>(value: &'a Value, path: &str) -> Option<&'a Value> {
    if path.is_empty() || path == "/" {
        Some(value)
    } else {
        value.pointer(path)
    }
}

/// Step `index`'s arguments with references replaced by the outputs of the
/// steps that ran (`outputs[n]` is step n's structured output).
pub fn resolve_arguments(arguments: &Value, outputs: &[Value]) -> Result<Value, String> {
    substitute(arguments, &mut String::new(), &mut |step, path, at| {
        let output = usize::try_from(step)
            .ok()
            .and_then(|s| outputs.get(s))
            .ok_or_else(|| format!("{at}: step {step} has not run"))?;
        pointer(output, path).cloned().ok_or_else(|| {
            format!(
                "{at}: step {step}'s output has nothing at {path} ({})",
                type_of(output)
            )
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decl::{Action, App, Entity, Param};
    use serde_json::json;
    use std::collections::HashMap;

    fn catalogue() -> HashMap<String, Value> {
        let notes = App {
            app_id: "org.example.notes".into(),
            actions: vec![Action {
                name: "notes.delete".into(),
                description: "Delete a note permanently.".into(),
                destructive: true,
                params: vec![Param {
                    required: true,
                    entity: Some("note".into()),
                    ..Param::new("note", "entity")
                }],
                ..Action::default()
            }],
            entities: vec![Entity {
                type_name: "note".into(),
                description: "A note.".into(),
                properties: vec![Param {
                    summarisable: true,
                    max_length: Some(32),
                    ..Param::new("created", "string")
                }],
                ..Entity::default()
            }],
            ..App::default()
        };
        let mail = App {
            app_id: "org.example.mail".into(),
            actions: vec![Action {
                name: "mail.compose".into(),
                description: "Compose a draft with an attachment.".into(),
                params: vec![
                    Param {
                        required: true,
                        entity: Some("org.example.notes/note".into()),
                        ..Param::new("attach", "entity")
                    },
                    Param {
                        required: true,
                        max_length: Some(100),
                        ..Param::new("to", "string")
                    },
                    Param {
                        max_length: Some(10),
                        ..Param::new("subject", "string")
                    },
                ],
                returns: Some(Param {
                    fields: vec!["draft".into()],
                    ..Param::new("", "object")
                }),
                ..Action::default()
            }],
            ..App::default()
        };
        let mut map = HashMap::new();
        for app in [notes, mail] {
            for t in app.manifest()["tools"].as_array().unwrap() {
                map.insert(t["name"].as_str().unwrap().to_owned(), t.clone());
            }
        }
        map
    }

    fn check(plan: &Value) -> Result<PlanSummary, Vec<String>> {
        let tools = catalogue();
        validate_plan(plan, &|name: &str| tools.get(name))
            .map_err(|e| e.into_iter().map(|e| e.to_string()).collect())
    }

    #[test]
    fn valid_plan_with_entity_reference() {
        let plan = json!({ "steps": [
            { "tool": "org.example.notes/note.find", "arguments": { "query": "yesterday", "limit": 1 } },
            { "tool": "org.example.mail/mail.compose", "arguments": { "attach": { "$step": 0, "path": "/items/0/uri" }, "to": "anna@example.org" } },
            { "tool": "org.example.notes/notes.delete", "arguments": { "note": { "$step": 0, "path": "/items/0/uri" } } }
        ] });
        let summary = check(&plan).unwrap();
        assert_eq!(summary.needs_confirmation, vec![2]);
        assert_eq!(summary.tools.len(), 3);
    }

    #[test]
    fn type_errors() {
        let plan = json!({ "steps": [
            { "tool": "org.example.notes/note.find", "arguments": { "query": "x" } },
            { "tool": "org.example.mail/mail.compose", "arguments": {
                "attach": { "$step": 0, "path": "/items/0/title" },
                "to": { "$step": 1, "path": "/draft" },
                "subject": { "$step": 0, "path": "/items/0/created" } } },
            { "tool": "org.example.mail/mail.compose", "arguments": { "attach": { "$step": 1, "path": "/draft" }, "to": "a", "cc": "b" } },
            { "tool": "org.example.notes/notes.fly", "arguments": {} },
            { "tool": "org.example.notes/notes.delete", "arguments": { "note": { "$step": 0, "path": "/items/0/nothing" } } }
        ] });
        let errors = check(&plan).unwrap_err();
        assert_eq!(errors, [
            "step 1: /attach: a plain string where a reference to org.example.notes/note is expected",
            "step 1: /to: refers to step 1, which does not run before this one",
            "step 2: /attach: a plain string where a reference to org.example.notes/note is expected",
            "step 2: /cc: unknown property",
            "step 3: no tool named org.example.notes/notes.fly",
            "step 4: /note: step 0's output has nothing at /items/0/nothing",
        ]);
    }

    #[test]
    fn literal_arguments_are_checked() {
        let plan = json!({ "steps": [ { "tool": "org.example.notes/notes.delete", "arguments": { "note": "n1" } } ] });
        assert_eq!(check(&plan).unwrap_err()[0], "step 0: /note: does not match the pattern ^keel://org\\.example\\.notes/note/[^/?#\\s]{1,256}$");
        assert!(check(&json!({ "steps": [] })).is_err());
    }

    #[test]
    fn resolves_outputs() {
        let outputs = vec![json!({ "items": [ { "uri": "keel://org.example.notes/note/n1" } ] })];
        let args = json!({ "attach": { "$step": 0, "path": "/items/0/uri" }, "to": "a" });
        assert_eq!(
            resolve_arguments(&args, &outputs).unwrap(),
            json!({ "attach": "keel://org.example.notes/note/n1", "to": "a" })
        );
        assert!(
            resolve_arguments(&json!({ "a": { "$step": 0, "path": "/x" } }), &outputs).is_err()
        );
    }
}
