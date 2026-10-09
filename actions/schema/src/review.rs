// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The rules Reef applies to an uploaded `actions.json` (ADR-0018,
//! decision 8), also run by `keel actions` so a developer sees them first:
//!
//! - `manifest`: version 1, an app ID, the expected one when given.
//! - `namespace`: every tool and prompt is `<app-id>/<name>`, at most 128
//!   characters of `A-Za-z0-9_-./`.
//! - `description`: every tool, entity type and prompt has a description of
//!   20 to 1,024 characters.
//! - `destructive`: a tool whose name or description says delete, remove,
//!   erase, wipe, overwrite, send, pay or purchase has `destructiveHint`, or
//!   says why not (`notDestructiveBecause`).
//! - `annotations`: all four hints present and boolean.
//! - `bounded`: every schema closed and bounded: strings with `maxLength`
//!   at most 1,000,000, arrays with `items` and `maxItems` at most 10,000,
//!   integers with `minimum` and `maximum`, objects with
//!   `additionalProperties: false`, at most 4 levels of nesting, `$ref`s
//!   only to local definitions.
//! - `entity`: every `x-keel-entity` of this app names a declared entity
//!   type; entity reference definitions carry a `keel://` pattern.
//! - `prompt`: every shortcut step names a tool of this app or an entity
//!   reference type's app.

use std::collections::BTreeSet;
use std::fmt;

use serde_json::Value;

use crate::bounds::{
    DESCRIPTION_MAX, DESCRIPTION_MIN, MAX_DEPTH, MAX_ITEMS_LIMIT, MAX_LENGTH_LIMIT, TOOL_NAME_MAX,
};
use crate::validate::escape_pointer;
use crate::{is_app_id, meta_key};

/// One rule broken.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    pub rule: &'static str,
    /// JSON pointer into the manifest.
    pub path: String,
    pub message: String,
}

impl fmt::Display for Finding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}] {}: {}", self.rule, self.path, self.message)
    }
}

const DESTRUCTIVE_WORDS: &[&str] = &[
    "delete",
    "deletes",
    "remove",
    "removes",
    "erase",
    "erases",
    "wipe",
    "wipes",
    "overwrite",
    "overwrites",
    "send",
    "sends",
    "pay",
    "pays",
    "purchase",
    "purchases",
];

struct Review {
    app_id: String,
    entity_types: BTreeSet<String>,
    findings: Vec<Finding>,
}

impl Review {
    fn add(&mut self, rule: &'static str, path: &str, message: impl Into<String>) {
        self.findings.push(Finding {
            rule,
            path: path.to_owned(),
            message: message.into(),
        });
    }

    fn description(&mut self, item: &Value, path: &str) {
        let n = item
            .get("description")
            .and_then(Value::as_str)
            .map_or(0, |d| d.trim().chars().count());
        if !(DESCRIPTION_MIN..=DESCRIPTION_MAX).contains(&n) {
            self.add(
                "description",
                &format!("{path}/description"),
                format!(
                    "a description of {DESCRIPTION_MIN} to {DESCRIPTION_MAX} characters saying what it does is required (has {n})"
                ),
            );
        }
    }

    fn name(&mut self, item: &Value, path: &str) {
        let name = item.get("name").and_then(Value::as_str).unwrap_or_default();
        let prefix = format!("{}/", self.app_id);
        let valid_chars = name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_-./".contains(c));
        if !name.starts_with(&prefix) || name.len() == prefix.len() {
            self.add(
                "namespace",
                &format!("{path}/name"),
                format!("\"{name}\" is not in the app's namespace {prefix}"),
            );
        } else if name.len() > TOOL_NAME_MAX || !valid_chars {
            self.add(
                "namespace",
                &format!("{path}/name"),
                format!("\"{name}\": at most {TOOL_NAME_MAX} characters of A-Z a-z 0-9 _ - . /"),
            );
        }
    }

    fn tool(&mut self, tool: &Value, path: &str) {
        self.name(tool, path);
        self.description(tool, path);
        let annotations = tool.get("annotations");
        for hint in [
            "readOnlyHint",
            "destructiveHint",
            "idempotentHint",
            "openWorldHint",
        ] {
            if !annotations
                .and_then(|a| a.get(hint))
                .is_some_and(Value::is_boolean)
            {
                self.add(
                    "annotations",
                    &format!("{path}/annotations/{hint}"),
                    "must be present (true or false)",
                );
            }
        }
        let destructive = annotations
            .and_then(|a| a.get("destructiveHint"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let excused = tool
            .get("_meta")
            .and_then(|m| m.get(meta_key("notDestructiveBecause")))
            .and_then(Value::as_str)
            .is_some_and(|w| !w.trim().is_empty());
        if !destructive && !excused {
            let text = format!(
                "{} {}",
                tool.get("name").and_then(Value::as_str).unwrap_or_default(),
                tool.get("description")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
            )
            .to_lowercase();
            if let Some(word) = text
                .split(|c: char| !c.is_ascii_alphanumeric())
                .find(|w| DESTRUCTIVE_WORDS.contains(w))
            {
                self.add(
                    "destructive",
                    &format!("{path}/annotations/destructiveHint"),
                    format!("says \"{word}\" but is not marked destructive; mark it, or say why not (notDestructiveBecause)"),
                );
            }
        }
        match tool.get("inputSchema") {
            Some(s) if s.get("type").and_then(Value::as_str) == Some("object") => {
                self.schema(s, s, &format!("{path}/inputSchema"), 0);
            }
            _ => self.add(
                "bounded",
                &format!("{path}/inputSchema"),
                "an object schema is required",
            ),
        }
        if let Some(s) = tool.get("outputSchema") {
            if s.get("type").and_then(Value::as_str) == Some("object") {
                self.schema(s, s, &format!("{path}/outputSchema"), 0);
            } else {
                self.add(
                    "bounded",
                    &format!("{path}/outputSchema"),
                    "an output schema is an object",
                );
            }
        }
    }

    fn schema(&mut self, schema: &Value, root: &Value, path: &str, depth: usize) {
        if let Some(reference) = schema.get("$ref").and_then(Value::as_str) {
            match reference.strip_prefix("#/$defs/") {
                Some(name) if root.get("$defs").and_then(|d| d.get(name)).is_some() => {
                    let def = &root["$defs"][name];
                    if def.get("x-keel-entity").is_some() {
                        self.entity_def(def, &format!("{path}(→{name})"));
                    } else {
                        self.schema(
                            def,
                            root,
                            &format!("/$defs/{}", escape_pointer(name)),
                            depth,
                        );
                    }
                }
                _ => self.add(
                    "bounded",
                    path,
                    format!("$ref {reference} does not resolve to a local definition"),
                ),
            }
            return;
        }
        let ty = schema.get("type").and_then(Value::as_str);
        match ty {
            Some("string") => match schema.get("maxLength").and_then(Value::as_u64) {
                Some(m) if m <= MAX_LENGTH_LIMIT => {}
                Some(m) => self.add("bounded", path, format!("maxLength {m} exceeds {MAX_LENGTH_LIMIT}")),
                None => self.add("bounded", path, "a string needs maxLength"),
            },
            Some("integer") => {
                if schema.get("minimum").is_none() || schema.get("maximum").is_none() {
                    self.add("bounded", path, "an integer needs minimum and maximum");
                }
            }
            Some("number" | "boolean") => {}
            Some("array") => {
                if depth >= MAX_DEPTH {
                    self.add("bounded", path, format!("nested deeper than {MAX_DEPTH} levels"));
                    return;
                }
                match schema.get("maxItems").and_then(Value::as_u64) {
                    Some(m) if m <= MAX_ITEMS_LIMIT => {}
                    Some(m) => self.add("bounded", path, format!("maxItems {m} exceeds {MAX_ITEMS_LIMIT}")),
                    None => self.add("bounded", path, "an array needs maxItems"),
                }
                match schema.get("items") {
                    Some(items) if items.is_object() => {
                        self.schema(items, root, &format!("{path}/items"), depth + 1);
                    }
                    _ => self.add("bounded", path, "an array needs an items schema"),
                }
            }
            Some("object") => {
                if depth >= MAX_DEPTH {
                    self.add("bounded", path, format!("nested deeper than {MAX_DEPTH} levels"));
                    return;
                }
                if schema.get("additionalProperties") != Some(&Value::Bool(false)) {
                    self.add("bounded", path, "an object needs additionalProperties: false");
                }
                if let Some(props) = schema.get("properties").and_then(Value::as_object) {
                    for (name, child) in props {
                        self.schema(
                            child,
                            root,
                            &format!("{path}/properties/{}", escape_pointer(name)),
                            depth + 1,
                        );
                    }
                }
            }
            _ => self.add("bounded", path, "every schema needs a type (string, integer, number, boolean, array, object) or a $ref"),
        }
    }

    fn entity_def(&mut self, def: &Value, path: &str) {
        let entity = def
            .get("x-keel-entity")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let pattern_ok = def
            .get("pattern")
            .and_then(Value::as_str)
            .is_some_and(|p| p.starts_with("^keel://"));
        let length_ok = def.get("maxLength").and_then(Value::as_u64).is_some();
        if !pattern_ok || !length_ok {
            self.add(
                "entity",
                path,
                "an entity reference needs a ^keel:// pattern and maxLength",
            );
        }
        if let Some((app, ty)) = entity.rsplit_once('/') {
            if app == self.app_id && !self.entity_types.contains(ty) {
                self.add(
                    "entity",
                    path,
                    format!("refers to entity type \"{ty}\", which the app does not declare"),
                );
            }
        } else {
            self.add(
                "entity",
                path,
                format!("\"{entity}\" is not <app-id>/<type>"),
            );
        }
    }
}

/// Reviews a manifest. `expected_app_id`: the app ID the package's desktop
/// file gives, when known.
pub fn review(manifest: &Value, expected_app_id: Option<&str>) -> Vec<Finding> {
    let app_id = manifest
        .get("appId")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let entity_types = manifest
        .get("entities")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|e| e.get("type").and_then(Value::as_str).map(ToOwned::to_owned))
        .collect();
    let mut r = Review {
        app_id: app_id.to_owned(),
        entity_types,
        findings: Vec::new(),
    };
    if manifest.get("version").and_then(Value::as_u64) != Some(1) {
        r.add("manifest", "/version", "must be 1");
    }
    if !is_app_id(app_id) {
        r.add(
            "manifest",
            "/appId",
            format!("\"{app_id}\" is not an app ID (OrganizationName.ApplicationName)"),
        );
    }
    if let Some(expected) = expected_app_id {
        if app_id != expected {
            r.add(
                "manifest",
                "/appId",
                format!("is \"{app_id}\", the desktop file says \"{expected}\""),
            );
        }
    }
    let tools = manifest
        .get("tools")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let tool_names: BTreeSet<String> = tools
        .iter()
        .filter_map(|t| t.get("name").and_then(Value::as_str).map(ToOwned::to_owned))
        .collect();
    if tool_names.len() != tools.len() {
        r.add("namespace", "/tools", "tool names must be unique");
    }
    for (i, tool) in tools.iter().enumerate() {
        r.tool(tool, &format!("/tools/{i}"));
    }
    for (i, entity) in manifest
        .get("entities")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .enumerate()
    {
        let path = format!("/entities/{i}");
        r.description(entity, &path);
        if let Some(schema) = entity.get("schema") {
            r.schema(schema, schema, &format!("{path}/schema"), 0);
        }
    }
    for (i, prompt) in manifest
        .get("prompts")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .enumerate()
    {
        let path = format!("/prompts/{i}");
        r.name(prompt, &path);
        r.description(prompt, &path);
        let steps = prompt
            .get("_meta")
            .and_then(|m| m.get(meta_key("steps")))
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        if steps.is_empty() {
            r.add("prompt", &path, "a shortcut needs at least one step");
        }
        for (j, step) in steps.iter().enumerate() {
            let tool = step.get("tool").and_then(Value::as_str).unwrap_or_default();
            if tool.starts_with(&format!("{app_id}/")) && !tool_names.contains(tool) {
                r.add(
                    "prompt",
                    &format!("{path}/_meta/steps/{j}"),
                    format!("step tool \"{tool}\" is not declared"),
                );
            }
        }
    }
    r.findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decl::{Action, App, Entity, Param};
    use serde_json::json;

    fn app() -> App {
        App {
            app_id: "org.example.notes".into(),
            actions: vec![Action {
                name: "notes.delete".into(),
                description: "Delete a note permanently from the device.".into(),
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
                description: "A note with a title and a body.".into(),
                ..Entity::default()
            }],
            ..App::default()
        }
    }

    #[test]
    fn generated_manifest_passes() {
        assert_eq!(review(&app().manifest(), Some("org.example.notes")), vec![]);
    }

    #[test]
    fn findings() {
        let mut a = app();
        a.actions[0].destructive = false;
        a.actions[0].params.push(Param {
            entity: Some("photo".into()),
            ..Param::new("p", "entity")
        });
        let mut m = a.manifest();
        // tools are sorted: 0 is note.find, 1 notes.delete.
        m["tools"][1]["inputSchema"]["properties"]["x"] = json!({ "type": "string" });
        m["tools"][1]["description"] = json!("Delete it.");
        let rules: Vec<_> = review(&m, Some("org.example.other"))
            .into_iter()
            .map(|f| f.rule)
            .collect();
        assert_eq!(
            rules,
            [
                "manifest",
                "description",
                "destructive",
                "entity",
                "bounded"
            ]
        );
    }
}
