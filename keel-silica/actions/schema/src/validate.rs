// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The JSON Schema subset Keel Actions use, and its validator (the same
//! rules as `keel/actions/plugin/keelschema.cpp`).
//!
//! Keywords: `type` (a name or a list), `properties`, `required`,
//! `additionalProperties` (only `false` constrains), `items`, `minItems`,
//! `maxItems`, `minLength`, `maxLength` (in characters), `pattern`, `enum`,
//! `minimum`, `maximum`, `$ref` (`#/$defs/<name>`). Annotations (`title`,
//! `description`, `default`, `format`, `x-keel-*`) do not constrain.

use std::fmt;

use serde_json::Value;

/// Where and why a value does not match.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Invalid {
    /// JSON pointer into the value ("" for the root).
    pub path: String,
    pub reason: String,
}

impl fmt::Display for Invalid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let path = if self.path.is_empty() {
            "/"
        } else {
            &self.path
        };
        write!(f, "{path}: {}", self.reason)
    }
}

impl std::error::Error for Invalid {}

/// The JSON type of a value, with whole numbers as "integer".
pub fn type_of(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(n) => {
            if n.is_i64() || n.is_u64() || n.as_f64().is_some_and(|f| f.fract() == 0.0) {
                "integer"
            } else {
                "number"
            }
        }
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

/// Escapes a JSON pointer token.
pub fn escape_pointer(token: &str) -> String {
    token.replace('~', "~0").replace('/', "~1")
}

/// Resolves a local `$ref` against `root`.
pub fn resolve<'a>(schema: &'a Value, root: &'a Value) -> Result<&'a Value, String> {
    let mut current = schema;
    for _ in 0..16 {
        let Some(reference) = current.get("$ref").and_then(Value::as_str) else {
            return Ok(current);
        };
        let name = reference
            .strip_prefix("#/$defs/")
            .ok_or_else(|| format!("unsupported $ref {reference}"))?;
        current = root
            .get("$defs")
            .and_then(|d| d.get(name))
            .ok_or_else(|| format!("unresolved $ref {reference}"))?;
    }
    Err("$ref chain too long".into())
}

/// Validates `value` against `schema` (whose `$defs` are in `schema`).
pub fn validate(schema: &Value, value: &Value) -> Result<(), Invalid> {
    validate_in(schema, value, schema)
}

/// Validates `value` against `schema`, resolving `$ref`s in `root`.
pub fn validate_in(schema: &Value, value: &Value, root: &Value) -> Result<(), Invalid> {
    check(schema, value, root, &mut String::new(), 0)
}

fn fail(path: &str, reason: impl Into<String>) -> Result<(), Invalid> {
    Err(Invalid {
        path: path.to_owned(),
        reason: reason.into(),
    })
}

fn type_matches(wanted: &str, actual: &str) -> bool {
    wanted == actual || (wanted == "number" && actual == "integer")
}

fn as_u64(schema: &Value, key: &str) -> Option<u64> {
    schema.get(key).and_then(Value::as_u64)
}

#[allow(clippy::too_many_lines, reason = "one match arm per keyword family")]
fn check(
    schema: &Value,
    value: &Value,
    root: &Value,
    path: &mut String,
    depth: usize,
) -> Result<(), Invalid> {
    if depth > 32 {
        return fail(path, "schema nests too deeply");
    }
    let schema = match resolve(schema, root) {
        Ok(s) => s,
        Err(e) => return fail(path, e),
    };
    let actual = type_of(value);
    if let Some(ty) = schema.get("type") {
        let wanted: Vec<&str> = match ty {
            Value::Array(list) => list.iter().filter_map(Value::as_str).collect(),
            Value::String(s) => vec![s.as_str()],
            _ => Vec::new(),
        };
        if !wanted.iter().any(|w| type_matches(w, actual)) {
            return fail(
                path,
                format!("expected {}, got {actual}", wanted.join(" or ")),
            );
        }
    }
    if let Some(Value::Array(allowed)) = schema.get("enum") {
        if !allowed.iter().any(|a| json_eq(a, value)) {
            return fail(path, "not one of the allowed values");
        }
    }
    match value {
        Value::String(s) => {
            let length = s.chars().count() as u64;
            if let Some(max) = as_u64(schema, "maxLength") {
                if length > max {
                    return fail(path, format!("longer than {max} characters"));
                }
            }
            if let Some(min) = as_u64(schema, "minLength") {
                if length < min {
                    return fail(path, format!("shorter than {min} characters"));
                }
            }
            if let Some(pattern) = schema.get("pattern").and_then(Value::as_str) {
                match regex::Regex::new(pattern) {
                    Ok(re) if re.is_match(s) => {}
                    Ok(_) => return fail(path, format!("does not match the pattern {pattern}")),
                    Err(_) => return fail(path, "invalid pattern in schema"),
                }
            }
        }
        Value::Number(n) => {
            let f = n.as_f64().unwrap_or(0.0);
            if let Some(min) = schema.get("minimum").and_then(Value::as_f64) {
                if f < min {
                    return fail(path, format!("below the minimum {min}"));
                }
            }
            if let Some(max) = schema.get("maximum").and_then(Value::as_f64) {
                if f > max {
                    return fail(path, format!("above the maximum {max}"));
                }
            }
        }
        Value::Array(items) => {
            if let Some(max) = as_u64(schema, "maxItems") {
                if items.len() as u64 > max {
                    return fail(path, format!("more than {max} items"));
                }
            }
            if let Some(min) = as_u64(schema, "minItems") {
                if (items.len() as u64) < min {
                    return fail(path, format!("fewer than {min} items"));
                }
            }
            if let Some(item_schema) = schema.get("items").filter(|s| s.is_object()) {
                for (i, item) in items.iter().enumerate() {
                    let len = path.len();
                    path.push('/');
                    path.push_str(&i.to_string());
                    check(item_schema, item, root, path, depth + 1)?;
                    path.truncate(len);
                }
            }
        }
        Value::Object(map) => {
            let properties = schema.get("properties").and_then(Value::as_object);
            if let Some(Value::Array(required)) = schema.get("required") {
                for name in required.iter().filter_map(Value::as_str) {
                    if !map.contains_key(name) {
                        return fail(path, format!("missing required property \"{name}\""));
                    }
                }
            }
            let closed = schema.get("additionalProperties") == Some(&Value::Bool(false));
            for (key, child) in map {
                let len = path.len();
                path.push('/');
                path.push_str(&escape_pointer(key));
                match properties.and_then(|p| p.get(key)) {
                    Some(child_schema) => check(child_schema, child, root, path, depth + 1)?,
                    None if closed => return fail(path, "unknown property"),
                    None => {}
                }
                path.truncate(len);
            }
        }
        Value::Null | Value::Bool(_) => {}
    }
    Ok(())
}

/// JSON equality with numbers compared by value (1 == 1.0).
pub fn json_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.as_f64() == y.as_f64(),
        (Value::Array(x), Value::Array(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| json_eq(p, q))
        }
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| y.get(k).is_some_and(|w| json_eq(v, w)))
        }
        _ => a == b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn schema() -> Value {
        json!({
            "type": "object",
            "properties": {
                "body": { "type": "string", "maxLength": 5, "minLength": 1 },
                "n": { "type": "integer", "minimum": 1, "maximum": 3 },
                "x": { "type": "number" },
                "tags": { "type": "array", "maxItems": 2, "items": { "type": "string", "enum": ["a", "b"] } },
                "note": { "$ref": "#/$defs/n" }
            },
            "required": ["body"],
            "additionalProperties": false,
            "$defs": { "n": { "type": "string", "pattern": "^keel://a\\.b/note/[^/?#\\s]{1,256}$" } }
        })
    }

    #[test]
    fn accepts_and_rejects() {
        let s = schema();
        assert!(validate(&s, &json!({ "body": "héllo", "n": 2.0, "x": 1, "tags": ["a"], "note": "keel://a.b/note/1" })).is_ok());
        let cases = [
            (json!({}), "/: missing required property \"body\""),
            (
                json!({ "body": "toolong" }),
                "/body: longer than 5 characters",
            ),
            (json!({ "body": "" }), "/body: shorter than 1 characters"),
            (
                json!({ "body": "a", "n": 1.5 }),
                "/n: expected integer, got number",
            ),
            (json!({ "body": "a", "n": 4 }), "/n: above the maximum 3"),
            (
                json!({ "body": "a", "tags": ["c"] }),
                "/tags/0: not one of the allowed values",
            ),
            (
                json!({ "body": "a", "tags": ["a", "b", "a"] }),
                "/tags: more than 2 items",
            ),
            (json!({ "body": "a", "y": 1 }), "/y: unknown property"),
            (
                json!({ "body": "a", "note": "keel://a.b/note/x/y" }),
                "/note: does not match the pattern ^keel://a\\.b/note/[^/?#\\s]{1,256}$",
            ),
            (json!([]), "/: expected object, got array"),
        ];
        for (value, message) in cases {
            assert_eq!(validate(&s, &value).unwrap_err().to_string(), message);
        }
    }
}
