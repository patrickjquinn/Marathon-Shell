// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! A minimal valid value for a schema: required properties only, the
//! default or the first allowed value where there is one, otherwise the
//! smallest value the bounds allow. Entity references become
//! `keel://<app>/<type>/example`. A `pattern` other than an entity's cannot
//! be satisfied in general; such strings are left empty and reported.

use std::fmt::Write as _;

use serde_json::{json, Map, Value};

use crate::validate::resolve;

/// The example and the JSON pointers of strings whose `pattern` it could
/// not satisfy.
pub fn example(schema: &Value) -> (Value, Vec<String>) {
    let mut unsatisfied = Vec::new();
    let value = build(schema, schema, &mut String::new(), &mut unsatisfied, 0);
    (value, unsatisfied)
}

fn build(
    schema: &Value,
    root: &Value,
    path: &mut String,
    unsatisfied: &mut Vec<String>,
    depth: usize,
) -> Value {
    let Ok(schema) = resolve(schema, root) else {
        return Value::Null;
    };
    if depth > 16 {
        return Value::Null;
    }
    if let Some(d) = schema.get("default") {
        return d.clone();
    }
    if let Some(first) = schema
        .get("enum")
        .and_then(Value::as_array)
        .and_then(|a| a.first())
    {
        return first.clone();
    }
    if let Some(entity) = schema.get("x-keel-entity").and_then(Value::as_str) {
        return json!(format!("keel://{entity}/example"));
    }
    let ty = match schema.get("type") {
        Some(Value::String(s)) => s.as_str(),
        Some(Value::Array(list)) => list.first().and_then(Value::as_str).unwrap_or("null"),
        _ => "null",
    };
    match ty {
        "object" => {
            let mut out = Map::new();
            let properties = schema.get("properties").and_then(Value::as_object);
            for name in schema
                .get("required")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
            {
                if let Some(child) = properties.and_then(|p| p.get(name)) {
                    let len = path.len();
                    path.push('/');
                    path.push_str(name);
                    out.insert(
                        name.to_owned(),
                        build(child, root, path, unsatisfied, depth + 1),
                    );
                    path.truncate(len);
                }
            }
            Value::Object(out)
        }
        "array" => {
            let min = schema.get("minItems").and_then(Value::as_u64).unwrap_or(0);
            let item = schema.get("items").cloned().unwrap_or(Value::Null);
            (0..min)
                .map(|i| {
                    let len = path.len();
                    let _ = write!(path, "/{i}");
                    let v = build(&item, root, path, unsatisfied, depth + 1);
                    path.truncate(len);
                    v
                })
                .collect()
        }
        "string" => {
            if schema.get("pattern").is_some() {
                unsatisfied.push(if path.is_empty() {
                    "/".into()
                } else {
                    path.clone()
                });
                return json!("");
            }
            let min = schema.get("minLength").and_then(Value::as_u64).unwrap_or(0);
            let n = usize::try_from(min.max(1)).unwrap_or(1);
            let max = schema
                .get("maxLength")
                .and_then(Value::as_u64)
                .and_then(|m| usize::try_from(m).ok())
                .unwrap_or(n);
            json!("x".repeat(n.min(max)))
        }
        "integer" | "number" => {
            let min = schema.get("minimum").and_then(Value::as_f64);
            let max = schema.get("maximum").and_then(Value::as_f64);
            let v = min.map_or(0.0, |m| m.max(0.0));
            let v = max.map_or(v, |m| v.min(m));
            let v = min.map_or(v, |m| v.max(m));
            if ty == "integer" {
                #[allow(
                    clippy::cast_possible_truncation,
                    reason = "bounds are 32-bit or JS-safe"
                )]
                let i = v.ceil() as i64;
                json!(i)
            } else {
                json!(v)
            }
        }
        "boolean" => json!(false),
        _ => Value::Null,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::validate::validate;

    #[test]
    fn examples_validate() {
        let schema = json!({
            "type": "object",
            "properties": {
                "q": { "type": "string", "maxLength": 10, "minLength": 2 },
                "n": { "type": "integer", "minimum": 1, "maximum": 50 },
                "neg": { "type": "integer", "minimum": -5, "maximum": -1 },
                "e": { "type": "string", "enum": ["x", "y"] },
                "r": { "$ref": "#/$defs/a.note" },
                "list": { "type": "array", "minItems": 1, "maxItems": 3, "items": { "type": "boolean" } },
                "opt": { "type": "string" }
            },
            "required": ["q", "n", "neg", "e", "r", "list"],
            "additionalProperties": false,
            "$defs": { "a.note": { "type": "string", "pattern": "^keel://a/note/[^/?#\\s]{1,256}$", "x-keel-entity": "a/note" } }
        });
        let (value, unsatisfied) = example(&schema);
        assert!(unsatisfied.is_empty());
        assert_eq!(value["r"], "keel://a/note/example");
        assert_eq!(value["neg"], -1);
        validate(&schema, &value).unwrap();
    }
}
