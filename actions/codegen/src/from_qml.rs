// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Declarations from QML files (`import Keel.Actions 1.0`).

use keel_actions_schema::decl::{Action, Entity, Param, Shortcut, Step};
use serde_json::{Map, Number, Value};

use crate::qml::{Document, QObject, QValue};
use crate::Diagnostics;

/// What one QML file declares.
#[derive(Default, Debug)]
pub struct Found {
    pub actions: Vec<Action>,
    pub entities: Vec<Entity>,
    pub contexts: usize,
    pub shortcuts: Vec<Shortcut>,
}

struct Reader<'a> {
    file: &'a str,
    /// The import alias of Keel.Actions, if any ("KA" for `KA.KeelAction`).
    alias: Option<String>,
    diag: &'a mut Diagnostics,
}

const PARAM_KEYS: &[&str] = &[
    "name",
    "type",
    "title",
    "description",
    "required",
    "maxLength",
    "minLength",
    "maxItems",
    "minimum",
    "maximum",
    "pattern",
    "format",
    "values",
    "entity",
    "itemType",
    "defaultValue",
    "fields",
    "properties",
    "summarisable",
    "indexable",
];
const ACTION_KEYS: &[&str] = &[
    "name",
    "title",
    "description",
    "readOnly",
    "destructive",
    "idempotent",
    "openWorld",
    "confirm",
    "sensitive",
    "untrusted",
    "notDestructiveBecause",
    "timeout",
    "parameters",
    "returns",
];
/// Bindings that may be expressions (run-time state).
const ACTION_RUNTIME: &[&str] = &["enabled", "id", "objectName"];
const ENTITY_KEYS: &[&str] = &["type", "title", "description", "properties"];
const SHORTCUT_KEYS: &[&str] = &["name", "title", "description", "arguments", "steps"];

/// JSON for a literal QML value (None for expressions and objects).
pub fn to_json(value: &QValue) -> Option<Value> {
    Some(match value {
        QValue::Str(s) => Value::String(s.clone()),
        QValue::Num(n) => {
            if n.fract() == 0.0 && n.abs() < 9.007_199_254_740_992e15 {
                #[allow(clippy::cast_possible_truncation, reason = "whole and below 2^53")]
                let i = *n as i64;
                Value::Number(i.into())
            } else {
                Value::Number(Number::from_f64(*n)?)
            }
        }
        QValue::Bool(b) => Value::Bool(*b),
        QValue::Null => Value::Null,
        QValue::List(items) => Value::Array(items.iter().map(to_json).collect::<Option<_>>()?),
        QValue::JsObject(entries) => {
            let mut map = Map::new();
            for (k, v) in entries {
                map.insert(k.clone(), to_json(v)?);
            }
            Value::Object(map)
        }
        QValue::Object(_) | QValue::Expr(_) => return None,
    })
}

impl Reader<'_> {
    fn local_type<'b>(&self, type_name: &'b str) -> Option<&'b str> {
        match (&self.alias, type_name.split_once('.')) {
            (Some(alias), Some((prefix, rest))) if prefix == alias => Some(rest),
            (None, None) => Some(type_name),
            _ => None,
        }
    }

    fn at(&self, line: usize) -> String {
        format!("{}:{line}", self.file)
    }

    fn error(&mut self, line: usize, message: impl Into<String>) {
        let at = self.at(line);
        self.diag.error(at, message);
    }

    /// The literal bindings of a declaration, checking for unknown and
    /// non-literal ones. Objects (`KeelParam` values) are kept.
    fn bindings<'o>(
        &mut self,
        object: &'o QObject,
        what: &str,
        keys: &[&str],
        runtime: &[&str],
    ) -> Vec<(&'o str, &'o QValue, usize)> {
        let mut out = Vec::new();
        for b in &object.bindings {
            let name = b.name.as_str();
            let handler =
                name.starts_with("on") && name[2..].starts_with(|c: char| c.is_uppercase());
            if handler || runtime.contains(&name) {
                continue;
            }
            if !keys.contains(&name) {
                self.error(
                    b.line,
                    format!(
                        "{what} has no property `{name}` (one of: {})",
                        keys.join(", ")
                    ),
                );
                continue;
            }
            if let QValue::Expr(text) = &b.value {
                self.error(
                    b.line,
                    format!("{what}.{name} must be a literal (the build step reads it statically), not `{text}`"),
                );
                continue;
            }
            out.push((name, &b.value, b.line));
        }
        out
    }

    fn string(&mut self, value: &QValue, line: usize, key: &str) -> Option<String> {
        if let QValue::Str(s) = value {
            Some(s.clone())
        } else {
            self.error(line, format!("`{key}` must be a string"));
            None
        }
    }

    fn boolean(&mut self, value: &QValue, line: usize, key: &str) -> bool {
        if let QValue::Bool(b) = value {
            *b
        } else {
            self.error(line, format!("`{key}` must be true or false"));
            false
        }
    }

    fn count(&mut self, value: &QValue, line: usize, key: &str) -> Option<u64> {
        match value {
            #[allow(
                clippy::cast_possible_truncation,
                clippy::cast_sign_loss,
                reason = "checked whole and non-negative"
            )]
            QValue::Num(n) if *n >= 0.0 && n.fract() == 0.0 => Some(*n as u64),
            _ => {
                self.error(line, format!("`{key}` must be a non-negative whole number"));
                None
            }
        }
    }

    fn param_objects(&mut self, value: &QValue, line: usize, key: &str) -> Vec<Param> {
        let items: Vec<&QValue> = match value {
            QValue::List(items) => items.iter().collect(),
            QValue::Object(_) => vec![value],
            _ => {
                self.error(line, format!("`{key}` must be a list of KeelParam"));
                return Vec::new();
            }
        };
        let mut out = Vec::new();
        for item in items {
            match item {
                QValue::Object(o) if self.local_type(&o.type_name) == Some("KeelParam") => {
                    out.push(self.param(o, "string"));
                }
                _ => self.error(line, format!("`{key}` must be a list of KeelParam")),
            }
        }
        out
    }

    fn param(&mut self, object: &QObject, default_type: &str) -> Param {
        let mut p = Param::new("", default_type);
        let what = self
            .local_type(&object.type_name)
            .unwrap_or("KeelParam")
            .to_owned();
        for (key, value, line) in self.bindings(object, &what, PARAM_KEYS, &["id"]) {
            match key {
                "name" => p.name = self.string(value, line, key).unwrap_or_default(),
                "type" => p.ty = self.string(value, line, key).unwrap_or_default(),
                "title" => p.title = self.string(value, line, key),
                "description" => p.description = self.string(value, line, key),
                "required" => p.required = self.boolean(value, line, key),
                "maxLength" => p.max_length = self.count(value, line, key),
                "minLength" => p.min_length = self.count(value, line, key),
                "maxItems" => p.max_items = self.count(value, line, key),
                "minimum" | "maximum" => {
                    let v = to_json(value).filter(Value::is_number);
                    if v.is_none() {
                        self.error(line, format!("`{key}` must be a number"));
                    }
                    if key == "minimum" {
                        p.minimum = v;
                    } else {
                        p.maximum = v;
                    }
                }
                "pattern" => p.pattern = self.string(value, line, key),
                "format" => p.format = self.string(value, line, key),
                "entity" => p.entity = self.string(value, line, key),
                "itemType" => p.item_type = self.string(value, line, key),
                "values" => match to_json(value) {
                    Some(Value::Array(v)) => p.values = v,
                    _ => self.error(line, "`values` must be a list of literals"),
                },
                "defaultValue" => p.default = to_json(value),
                "fields" => match to_json(value) {
                    Some(Value::Array(v)) if v.iter().all(Value::is_string) => {
                        p.fields = v
                            .iter()
                            .filter_map(|s| s.as_str().map(ToOwned::to_owned))
                            .collect();
                    }
                    _ => self.error(line, "`fields` must be a list of strings"),
                },
                "properties" => p.properties = self.param_objects(value, line, key),
                "summarisable" => p.summarisable = self.boolean(value, line, key),
                "indexable" => p.indexable = self.boolean(value, line, key),
                _ => {}
            }
        }
        for child in &object.children {
            if self.local_type(&child.type_name) == Some("KeelParam") {
                p.properties.push(self.param(child, "string"));
            } else {
                self.error(
                    child.line,
                    format!("{what} may only contain KeelParam objects"),
                );
            }
        }
        self.check_param(&p, object.line, &what);
        p
    }

    fn check_param(&mut self, p: &Param, line: usize, what: &str) {
        const TYPES: &[&str] = &[
            "string", "integer", "number", "boolean", "entity", "array", "object",
        ];
        if what == "KeelParam"
            && (p.name.is_empty()
                || !p
                    .name
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_'))
        {
            self.error(
                line,
                format!(
                    "a KeelParam needs a name of letters, digits and _ (got \"{}\")",
                    p.name
                ),
            );
        }
        let ok_type = TYPES.contains(&p.ty.as_str()) || (what == "KeelResult" && p.ty == "none");
        if !ok_type {
            self.error(
                line,
                format!(
                    "{what} \"{}\": unknown type \"{}\" (one of: {})",
                    p.name,
                    p.ty,
                    TYPES.join(", ")
                ),
            );
        }
        let item = p.item_type.as_deref().unwrap_or("string");
        if p.ty == "array"
            && !["string", "integer", "number", "boolean", "entity", "object"].contains(&item)
        {
            self.error(line, format!("{what} \"{}\": itemType \"{item}\" is not supported (arrays of arrays are not)", p.name));
        }
        if (p.ty == "entity" || (p.ty == "array" && item == "entity"))
            && p.entity.as_deref().unwrap_or("").is_empty()
        {
            self.error(
                line,
                format!("{what} \"{}\": an entity reference needs `entity`", p.name),
            );
        }
        if let Some(pattern) = &p.pattern {
            if regex_check(pattern).is_err() {
                self.error(
                    line,
                    format!("{what} \"{}\": invalid pattern {pattern}", p.name),
                );
            }
        }
    }

    fn action(&mut self, object: &QObject) -> Action {
        let mut a = Action {
            source: self.at(object.line),
            ..Action::default()
        };
        for (key, value, line) in self.bindings(object, "KeelAction", ACTION_KEYS, ACTION_RUNTIME) {
            match key {
                "name" => a.name = self.string(value, line, key).unwrap_or_default(),
                "title" => a.title = self.string(value, line, key),
                "description" => a.description = self.string(value, line, key).unwrap_or_default(),
                "readOnly" => a.read_only = self.boolean(value, line, key),
                "destructive" => a.destructive = self.boolean(value, line, key),
                "idempotent" => a.idempotent = self.boolean(value, line, key),
                "openWorld" => a.open_world = self.boolean(value, line, key),
                "confirm" => a.confirm = self.boolean(value, line, key),
                "sensitive" => a.sensitive = self.boolean(value, line, key),
                "untrusted" => a.untrusted = self.boolean(value, line, key),
                "notDestructiveBecause" => {
                    a.not_destructive_because = self.string(value, line, key);
                }
                "timeout" => a.timeout_ms = self.count(value, line, key).unwrap_or(25_000),
                "parameters" => a.params = self.param_objects(value, line, key),
                "returns" => match value {
                    QValue::Object(o) if self.local_type(&o.type_name) == Some("KeelResult") => {
                        let r = self.param(o, "none");
                        a.returns = (r.ty != "none").then_some(r);
                    }
                    _ => self.error(line, "`returns` must be a KeelResult"),
                },
                _ => {}
            }
        }
        a
    }

    fn entity(&mut self, object: &QObject) -> Entity {
        let mut e = Entity {
            source: self.at(object.line),
            ..Entity::default()
        };
        for (key, value, line) in self.bindings(object, "KeelEntity", ENTITY_KEYS, &["id"]) {
            match key {
                "type" => e.type_name = self.string(value, line, key).unwrap_or_default(),
                "title" => e.title = self.string(value, line, key),
                "description" => e.description = self.string(value, line, key).unwrap_or_default(),
                "properties" => e.properties = self.param_objects(value, line, key),
                _ => {}
            }
        }
        for child in &object.children {
            if self.local_type(&child.type_name) == Some("KeelParam") {
                e.properties.push(self.param(child, "string"));
            } else {
                self.error(child.line, "KeelEntity may only contain KeelParam objects");
            }
        }
        e
    }

    fn shortcut(&mut self, object: &QObject) -> Shortcut {
        let mut s = Shortcut {
            source: self.at(object.line),
            ..Shortcut::default()
        };
        for (key, value, line) in self.bindings(object, "KeelShortcut", SHORTCUT_KEYS, &["id"]) {
            match key {
                "name" => s.name = self.string(value, line, key).unwrap_or_default(),
                "title" => s.title = self.string(value, line, key),
                "description" => s.description = self.string(value, line, key).unwrap_or_default(),
                "arguments" => s.arguments = self.param_objects(value, line, key),
                "steps" => match to_json(value) {
                    Some(Value::Array(steps)) => {
                        for step in steps {
                            match step.get("action").and_then(Value::as_str) {
                                Some(action) => s.steps.push(Step {
                                    action: action.to_owned(),
                                    arguments: step
                                        .get("arguments")
                                        .cloned()
                                        .unwrap_or(Value::Object(Map::new())),
                                }),
                                None => self.error(
                                    line,
                                    "each step is { action: \"...\", arguments: { ... } }",
                                ),
                            }
                        }
                    }
                    _ => self.error(
                        line,
                        "`steps` must be a list of { action, arguments } literals",
                    ),
                },
                _ => {}
            }
        }
        s
    }

    fn walk(&mut self, object: &QObject, found: &mut Found) {
        match self.local_type(&object.type_name) {
            Some("KeelAction") => found.actions.push(self.action(object)),
            Some("KeelEntity") => {
                found.entities.push(self.entity(object));
                return;
            }
            Some("KeelContext") => found.contexts += 1,
            Some("KeelShortcut") => found.shortcuts.push(self.shortcut(object)),
            _ => {}
        }
        for child in &object.children {
            self.walk(child, found);
        }
        for b in &object.bindings {
            let mut values = vec![&b.value];
            while let Some(v) = values.pop() {
                match v {
                    QValue::Object(o)
                        if !matches!(
                            self.local_type(&o.type_name),
                            Some("KeelParam" | "KeelResult")
                        ) =>
                    {
                        self.walk(o, found);
                    }
                    QValue::List(items) => values.extend(items),
                    _ => {}
                }
            }
        }
    }
}

fn regex_check(pattern: &str) -> Result<(), String> {
    keel_actions_schema::validate::validate(
        &serde_json::json!({ "type": "string", "pattern": pattern }),
        &Value::String(String::new()),
    )
    .map_err(|e| e.reason)
    .or_else(|reason| {
        if reason == "invalid pattern in schema" {
            Err(reason)
        } else {
            Ok(())
        }
    })
}

/// The declarations in a parsed QML document (`file` names it in messages).
pub fn read(doc: &Document, file: &str, diag: &mut Diagnostics) -> Found {
    let mut found = Found::default();
    let Some(import) = doc.imports.iter().find(|i| i.uri == "Keel.Actions") else {
        return found;
    };
    let mut reader = Reader {
        file,
        alias: import.alias.clone(),
        diag,
    };
    reader.walk(&doc.root, &mut found);
    found
}
