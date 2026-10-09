// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Declarations (what `KeelAction`, `KeelEntity`, `KeelContext`,
//! `KeelShortcut` and `#[keel::action]` say) and the manifest they generate.
//!
//! The mapping is the one in `keel/actions/plugin/keeldeclarations.cpp`;
//! change both together.

use serde_json::{json, Map, Value};

use crate::bounds::{
    DEFAULT_INT_MAX, DEFAULT_INT_MIN, DEFAULT_MAX_ITEMS, DEFAULT_MAX_LENGTH, DEFAULT_TIMEOUT_MS,
    FIND_LIMIT_MAX, FIND_QUERY_MAX_LENGTH, ID_MAX_LENGTH, TITLE_MAX_LENGTH,
};
use crate::{escape_regex, meta_key};

/// A typed value: parameter, result, field or entity property.
#[derive(Clone, Debug, Default, PartialEq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "one flag per declared property, as in KeelParam"
)]
pub struct Param {
    pub name: String,
    /// string, integer, number, boolean, entity, array, object, none.
    pub ty: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub required: bool,
    pub max_length: Option<u64>,
    pub min_length: Option<u64>,
    pub max_items: Option<u64>,
    pub minimum: Option<Value>,
    pub maximum: Option<Value>,
    pub pattern: Option<String>,
    pub format: Option<String>,
    pub values: Vec<Value>,
    pub entity: Option<String>,
    pub item_type: Option<String>,
    pub default: Option<Value>,
    pub fields: Vec<String>,
    pub properties: Vec<Param>,
    pub summarisable: bool,
    pub indexable: bool,
}

impl Param {
    pub fn new(name: &str, ty: &str) -> Self {
        Self {
            name: name.to_owned(),
            ty: ty.to_owned(),
            ..Self::default()
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "one flag per declared hint, as in KeelAction"
)]
pub struct Action {
    pub name: String,
    pub title: Option<String>,
    pub description: String,
    pub read_only: bool,
    pub destructive: bool,
    pub idempotent: bool,
    pub open_world: bool,
    pub confirm: bool,
    pub sensitive: bool,
    /// The result carries content the app does not vouch for (web pages,
    /// messages from others): data for a model, never instructions.
    pub untrusted: bool,
    pub not_destructive_because: Option<String>,
    pub timeout_ms: u64,
    pub params: Vec<Param>,
    /// None, or a `Param` whose type is not "none".
    pub returns: Option<Param>,
    /// Where it was declared (`file:line`), for messages.
    pub source: String,
    /// Implemented in Rust (`#[keel::action]`).
    pub native: bool,
}

impl Default for Action {
    fn default() -> Self {
        Self {
            name: String::new(),
            title: None,
            description: String::new(),
            read_only: false,
            destructive: false,
            idempotent: false,
            open_world: false,
            confirm: false,
            sensitive: false,
            untrusted: false,
            not_destructive_because: None,
            timeout_ms: DEFAULT_TIMEOUT_MS,
            params: Vec::new(),
            returns: None,
            source: String::new(),
            native: false,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Entity {
    pub type_name: String,
    pub title: Option<String>,
    pub description: String,
    pub properties: Vec<Param>,
    pub source: String,
    pub native: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Step {
    pub action: String,
    pub arguments: Value,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Shortcut {
    pub name: String,
    pub title: Option<String>,
    pub description: String,
    pub arguments: Vec<Param>,
    pub steps: Vec<Step>,
    pub source: String,
}

/// Everything an app declares.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct App {
    pub app_id: String,
    pub actions: Vec<Action>,
    pub entities: Vec<Entity>,
    pub context: bool,
    pub shortcuts: Vec<Shortcut>,
}

fn obj(pairs: Vec<(&str, Value)>) -> Map<String, Value> {
    pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect()
}

/// `<type>` of `app_id`, or `<app-id>/<type>` as given.
pub fn qualified_entity(entity: &str, app_id: &str) -> String {
    if entity.contains('/') {
        entity.to_owned()
    } else {
        format!("{app_id}/{entity}")
    }
}

/// The `$defs` key of an entity reference.
pub fn entity_def_name(qualified: &str) -> String {
    qualified.replace('/', ".")
}

/// The definition of an entity reference: a `keel://` URI string.
pub fn entity_ref_def(qualified: &str) -> Value {
    let (app, ty) = qualified.rsplit_once('/').unwrap_or(("", qualified));
    let prefix = format!("keel://{app}/{ty}/");
    let pattern = format!("^{}[^/?#\\s]{{1,{ID_MAX_LENGTH}}}$", escape_regex(&prefix));
    json!({
        "type": "string",
        "format": "uri",
        "pattern": pattern,
        "maxLength": prefix.len() as u64 + ID_MAX_LENGTH,
        "x-keel-entity": qualified,
    })
}

/// A `$ref` to an entity reference, adding its definition to `defs`.
pub fn entity_ref(qualified: &str, defs: &mut Map<String, Value>) -> Value {
    let name = entity_def_name(qualified);
    defs.entry(name.clone())
        .or_insert_with(|| entity_ref_def(qualified));
    json!({ "$ref": format!("#/$defs/{name}") })
}

/// A closed object schema.
pub fn object(properties: Map<String, Value>, required: &[String]) -> Value {
    let mut s = obj(vec![
        ("type", json!("object")),
        ("properties", Value::Object(properties)),
        ("additionalProperties", json!(false)),
    ]);
    if !required.is_empty() {
        s.insert("required".into(), json!(required));
    }
    Value::Object(s)
}

/// MCP output schemas are objects: other results are `{ "result": ... }`.
pub fn wrap_result(schema: Value) -> Value {
    let mut properties = Map::new();
    properties.insert("result".into(), schema);
    object(properties, &["result".to_owned()])
}

fn with_defs(mut schema: Value, defs: Map<String, Value>) -> Value {
    if !defs.is_empty() {
        if let Value::Object(map) = &mut schema {
            map.insert("$defs".into(), Value::Object(defs));
        }
    }
    schema
}

/// Integers as integers: Qt writes whole doubles without a fraction.
fn number(value: &Value) -> Value {
    match value.as_f64() {
        Some(f) if f.fract() == 0.0 && f.abs() < 9.007_199_254_740_992e15 => {
            #[allow(clippy::cast_possible_truncation, reason = "whole and below 2^53")]
            let i = f as i64;
            json!(i)
        }
        _ => value.clone(),
    }
}

impl Param {
    fn object_schema(&self, app_id: &str, defs: &mut Map<String, Value>) -> Value {
        let mut properties = Map::new();
        let mut required = Vec::new();
        for field in &self.fields {
            properties.insert(
                field.clone(),
                json!({ "type": "string", "maxLength": DEFAULT_MAX_LENGTH }),
            );
            required.push(field.clone());
        }
        for p in &self.properties {
            properties.insert(p.name.clone(), p.schema(app_id, defs));
            if p.required {
                required.push(p.name.clone());
            }
        }
        object(properties, &required)
    }

    fn scalar_schema(&self, ty: &str, app_id: &str, defs: &mut Map<String, Value>) -> Value {
        match ty {
            "entity" => {
                return entity_ref(
                    &qualified_entity(self.entity.as_deref().unwrap_or_default(), app_id),
                    defs,
                )
            }
            "object" => return self.object_schema(app_id, defs),
            _ => {}
        }
        let mut s = Map::new();
        match ty {
            "integer" => {
                s.insert("type".into(), json!("integer"));
                s.insert(
                    "minimum".into(),
                    self.minimum.as_ref().map_or(json!(DEFAULT_INT_MIN), number),
                );
                s.insert(
                    "maximum".into(),
                    self.maximum.as_ref().map_or(json!(DEFAULT_INT_MAX), number),
                );
            }
            "number" => {
                s.insert("type".into(), json!("number"));
                if let Some(m) = &self.minimum {
                    s.insert("minimum".into(), number(m));
                }
                if let Some(m) = &self.maximum {
                    s.insert("maximum".into(), number(m));
                }
            }
            "boolean" => {
                s.insert("type".into(), json!("boolean"));
            }
            _ => {
                s.insert("type".into(), json!("string"));
                s.insert(
                    "maxLength".into(),
                    json!(self.max_length.unwrap_or(DEFAULT_MAX_LENGTH)),
                );
                if let Some(min) = self.min_length.filter(|m| *m > 0) {
                    s.insert("minLength".into(), json!(min));
                }
                if let Some(p) = &self.pattern {
                    s.insert("pattern".into(), json!(p));
                }
                if let Some(f) = &self.format {
                    s.insert("format".into(), json!(f));
                }
            }
        }
        if !self.values.is_empty() {
            s.insert("enum".into(), Value::Array(self.values.clone()));
        }
        Value::Object(s)
    }

    /// The JSON Schema of this value.
    pub fn schema(&self, app_id: &str, defs: &mut Map<String, Value>) -> Value {
        let mut s = if self.ty == "array" {
            let items =
                self.scalar_schema(self.item_type.as_deref().unwrap_or("string"), app_id, defs);
            json!({
                "type": "array",
                "maxItems": self.max_items.unwrap_or(DEFAULT_MAX_ITEMS),
                "items": items,
            })
        } else {
            self.scalar_schema(&self.ty, app_id, defs)
        };
        let Some(map) = s.as_object_mut() else {
            return s;
        };
        if let Some(t) = &self.title {
            map.insert("title".into(), json!(t));
        }
        if let Some(d) = &self.description {
            map.insert("description".into(), json!(d));
        }
        if let Some(d) = &self.default {
            map.insert("default".into(), d.clone());
        }
        if self.summarisable {
            map.insert("x-keel-summarisable".into(), json!(true));
        }
        if self.indexable {
            map.insert("x-keel-indexable".into(), json!(true));
        }
        s
    }
}

fn params_schema(params: &[Param], app_id: &str) -> Value {
    let mut defs = Map::new();
    let mut properties = Map::new();
    let mut required = Vec::new();
    for p in params {
        properties.insert(p.name.clone(), p.schema(app_id, &mut defs));
        if p.required {
            required.push(p.name.clone());
        }
    }
    with_defs(object(properties, &required), defs)
}

#[allow(clippy::fn_params_excessive_bools, reason = "the four MCP hints")]
fn hints(read_only: bool, destructive: bool, idempotent: bool, open_world: bool) -> Value {
    json!({
        "readOnlyHint": read_only,
        "destructiveHint": destructive,
        "idempotentHint": idempotent,
        "openWorldHint": open_world,
    })
}

impl Action {
    pub fn has_result(&self) -> bool {
        self.returns.as_ref().is_some_and(|r| r.ty != "none")
    }

    /// The MCP tool.
    pub fn tool(&self, app_id: &str) -> Value {
        let mut tool = obj(vec![
            ("name", json!(format!("{app_id}/{}", self.name))),
            ("description", json!(self.description)),
            ("inputSchema", params_schema(&self.params, app_id)),
            (
                "annotations",
                hints(
                    self.read_only,
                    self.destructive,
                    self.idempotent,
                    self.open_world,
                ),
            ),
        ]);
        if let Some(t) = &self.title {
            tool.insert("title".into(), json!(t));
        }
        let mut kind = "none";
        if let Some(r) = self.returns.as_ref().filter(|_| self.has_result()) {
            let mut defs = Map::new();
            let mut output = r.schema(app_id, &mut defs);
            if r.ty == "object" {
                kind = "object";
            } else {
                output = wrap_result(output);
                kind = "wrapped";
            }
            tool.insert("outputSchema".into(), with_defs(output, defs));
        }
        let mut meta = obj(vec![
            (&meta_key("action"), json!(self.name)),
            (&meta_key("confirm"), json!(self.confirm)),
            (&meta_key("sensitive"), json!(self.sensitive)),
            (&meta_key("result"), json!(kind)),
            (&meta_key("timeoutMs"), json!(self.timeout_ms)),
        ]);
        if let Some(why) = &self.not_destructive_because {
            meta.insert(meta_key("notDestructiveBecause"), json!(why));
        }
        // Only when set, so manifests without it stay as they were.
        if self.untrusted {
            meta.insert(meta_key("untrusted"), json!(true));
        }
        tool.insert("_meta".into(), Value::Object(meta));
        Value::Object(tool)
    }
}

impl Entity {
    fn entity_schema(&self, app_id: &str, defs: &mut Map<String, Value>, summary: bool) -> Value {
        let mut properties = Map::new();
        properties.insert(
            "uri".into(),
            entity_ref(&format!("{app_id}/{}", self.type_name), defs),
        );
        properties.insert(
            "id".into(),
            json!({ "type": "string", "maxLength": ID_MAX_LENGTH }),
        );
        properties.insert(
            "title".into(),
            json!({ "type": "string", "maxLength": TITLE_MAX_LENGTH }),
        );
        let mut required: Vec<String> = vec!["uri".into(), "id".into(), "title".into()];
        for p in &self.properties {
            if summary && !p.summarisable {
                continue;
            }
            properties.insert(p.name.clone(), p.schema(app_id, defs));
            if p.required {
                required.push(p.name.clone());
            }
        }
        object(properties, &required)
    }

    fn display(&self) -> &str {
        self.title.as_deref().unwrap_or(&self.type_name)
    }

    /// The `<app-id>/<type>.find` tool.
    pub fn find_tool(&self, app_id: &str) -> Value {
        let what = self.display();
        let mut defs = Map::new();
        let items = json!({
            "type": "array",
            "maxItems": FIND_LIMIT_MAX,
            "items": self.entity_schema(app_id, &mut defs, true),
        });
        let mut input_props = Map::new();
        input_props.insert(
            "query".into(),
            json!({
                "type": "string",
                "maxLength": FIND_QUERY_MAX_LENGTH,
                "description": "Text to look for; empty for the most recent.",
            }),
        );
        input_props.insert(
            "limit".into(),
            json!({ "type": "integer", "minimum": 1, "maximum": FIND_LIMIT_MAX, "default": 10 }),
        );
        let mut output_props = Map::new();
        output_props.insert("items".into(), items);
        let mut description = format!(
            "Find {what} items by text. Returns references (uri, id, title) for later steps."
        );
        if !self.description.is_empty() {
            description.push(' ');
            description.push_str(&self.description);
        }
        json!({
            "name": format!("{app_id}/{}.find", self.type_name),
            "title": format!("Find {what}"),
            "description": description,
            "inputSchema": object(input_props, &["query".to_owned()]),
            "outputSchema": with_defs(object(output_props, &["items".to_owned()]), defs),
            "annotations": hints(true, false, true, false),
            "_meta": {
                meta_key("find"): self.type_name,
                meta_key("confirm"): false,
                meta_key("sensitive"): false,
                meta_key("result"): "object",
                meta_key("timeoutMs"): DEFAULT_TIMEOUT_MS,
            },
        })
    }

    /// The manifest's `entities` entry.
    pub fn manifest_entry(&self, app_id: &str) -> Value {
        let mut defs = Map::new();
        let schema = self.entity_schema(app_id, &mut defs, false);
        json!({
            "type": self.type_name,
            "title": self.display(),
            "description": self.description,
            "uriTemplate": format!("keel://{app_id}/{}/{{id}}", self.type_name),
            "findTool": format!("{app_id}/{}.find", self.type_name),
            "schema": with_defs(schema, defs),
        })
    }
}

impl Shortcut {
    /// The MCP prompt.
    pub fn prompt(&self, app_id: &str) -> Value {
        let arguments: Vec<Value> = self
            .arguments
            .iter()
            .map(|p| {
                let mut a = obj(vec![
                    ("name", json!(p.name)),
                    ("required", json!(p.required)),
                ]);
                if let Some(d) = &p.description {
                    a.insert("description".into(), json!(d));
                }
                Value::Object(a)
            })
            .collect();
        let steps: Vec<Value> = self
            .steps
            .iter()
            .map(|s| {
                let tool = if s.action.contains('/') {
                    s.action.clone()
                } else {
                    format!("{app_id}/{}", s.action)
                };
                let arguments = if s.arguments.is_null() {
                    json!({})
                } else {
                    s.arguments.clone()
                };
                json!({ "tool": tool, "arguments": arguments })
            })
            .collect();
        let mut prompt = obj(vec![
            ("name", json!(format!("{app_id}/{}", self.name))),
            ("description", json!(self.description)),
            ("arguments", Value::Array(arguments)),
            ("_meta", json!({ meta_key("steps"): steps })),
        ]);
        if let Some(t) = &self.title {
            prompt.insert("title".into(), json!(t));
        }
        Value::Object(prompt)
    }
}

fn sorted_by(mut values: Vec<Value>, key: &str) -> Value {
    values.sort_by(|a, b| {
        a[key]
            .as_str()
            .unwrap_or_default()
            .cmp(b[key].as_str().unwrap_or_default())
    });
    Value::Array(values)
}

impl App {
    /// The manifest, `actions.json`.
    pub fn manifest(&self) -> Value {
        let id = &self.app_id;
        let mut tools: Vec<Value> = self.actions.iter().map(|a| a.tool(id)).collect();
        tools.extend(self.entities.iter().map(|e| e.find_tool(id)));
        let entities: Vec<Value> = self.entities.iter().map(|e| e.manifest_entry(id)).collect();
        let prompts: Vec<Value> = self.shortcuts.iter().map(|s| s.prompt(id)).collect();
        let mut m = obj(vec![
            ("version", json!(1)),
            ("appId", json!(id)),
            ("tools", sorted_by(tools, "name")),
            ("entities", sorted_by(entities, "type")),
            ("prompts", sorted_by(prompts, "name")),
        ]);
        if self.context {
            m.insert(
                "context".into(),
                json!({ "uri": format!("keel://{id}/context") }),
            );
        }
        Value::Object(m)
    }
}
