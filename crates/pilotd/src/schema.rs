// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! A small JSON Schema validator for tool-call arguments (spec section 6.1:
//! "tool calls validated against JSON schemas in `pilotd` before
//! execution") and MCP `outputSchema` checks (section 9.3).
//!
//! It covers the subset Keel Actions and the system tool registry emit:
//! `type` (one or a list), `properties`, `required`,
//! `additionalProperties` (boolean or schema), `enum`, `const`,
//! `minLength`/`maxLength`, `pattern`, `format` (`date-time`, `date`,
//! `time`), `minimum`/`maximum` and their exclusive forms, `items`,
//! `minItems`/`maxItems`, `uniqueItems`, `allOf`/`anyOf`/`oneOf`/`not`, and
//! local `$ref` (`#/$defs/...`, `#/definitions/...`). Any other keyword
//! fails [`Validator::check_schema`], so a schema this module cannot
//! enforce is refused at registration instead of silently accepted.

use regex::Regex;
use serde_json::{Map, Value};

/// Keywords this validator understands, or that are annotations only.
const KNOWN: &[&str] = &[
    "type",
    "properties",
    "required",
    "additionalProperties",
    "enum",
    "const",
    "minLength",
    "maxLength",
    "pattern",
    "format",
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "items",
    "minItems",
    "maxItems",
    "uniqueItems",
    "allOf",
    "anyOf",
    "oneOf",
    "not",
    "$ref",
    "$defs",
    "definitions",
    "$schema",
    "$id",
    "title",
    "description",
    "default",
    "examples",
    "readOnly",
    "writeOnly",
    "deprecated",
    // Keel Actions: an entity reference's target type (section 9.7); its
    // shape is still checked by the rest of the schema.
    "x-keel-entity",
    "x-keel-summarisable",
];

/// Deepest nesting followed through `$ref` and combinators, against
/// self-referencing schemas.
const MAX_DEPTH: usize = 32;

/// One violation, with a JSON Pointer to the offending value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Violation {
    pub path: String,
    pub message: String,
}

impl std::fmt::Display for Violation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let path = if self.path.is_empty() {
            "/"
        } else {
            &self.path
        };
        write!(f, "{path}: {}", self.message)
    }
}

/// A schema ready to validate against.
#[derive(Debug, Clone)]
pub struct Validator {
    root: Value,
}

impl Validator {
    /// Wraps `schema` after checking that every keyword is one this module
    /// enforces and every `pattern` compiles.
    pub fn new(schema: Value) -> Result<Validator, String> {
        Self::check_schema(&schema, "", 0)?;
        Ok(Validator { root: schema })
    }

    pub fn schema(&self) -> &Value {
        &self.root
    }

    fn check_schema(schema: &Value, at: &str, depth: usize) -> Result<(), String> {
        if depth > MAX_DEPTH {
            return Err(format!("{at}: schema nested too deeply"));
        }
        let obj = match schema {
            Value::Bool(_) => return Ok(()),
            Value::Object(o) => o,
            _ => return Err(format!("{at}: a schema must be an object or a boolean")),
        };
        for (k, v) in obj {
            if !KNOWN.contains(&k.as_str()) && !k.starts_with("x-") {
                return Err(format!("{at}: unsupported keyword {k}"));
            }
            let here = format!("{at}/{k}");
            match k.as_str() {
                "properties" | "$defs" | "definitions" => {
                    let Value::Object(props) = v else {
                        return Err(format!("{here}: must be an object"));
                    };
                    for (name, sub) in props {
                        Self::check_schema(sub, &format!("{here}/{name}"), depth + 1)?;
                    }
                }
                "items" | "additionalProperties" | "not" => {
                    Self::check_schema(v, &here, depth + 1)?;
                }
                "allOf" | "anyOf" | "oneOf" => {
                    let Value::Array(subs) = v else {
                        return Err(format!("{here}: must be an array"));
                    };
                    for (i, sub) in subs.iter().enumerate() {
                        Self::check_schema(sub, &format!("{here}/{i}"), depth + 1)?;
                    }
                }
                "pattern" => {
                    let Value::String(p) = v else {
                        return Err(format!("{here}: must be a string"));
                    };
                    Regex::new(p).map_err(|e| format!("{here}: {e}"))?;
                }
                "$ref" => {
                    let Value::String(r) = v else {
                        return Err(format!("{here}: must be a string"));
                    };
                    if !(r.starts_with("#/$defs/") || r.starts_with("#/definitions/") || r == "#") {
                        return Err(format!("{here}: only local references are supported"));
                    }
                }
                _ => {}
            }
        }
        Ok(())
    }

    /// All violations of the schema by `value`; empty when valid.
    pub fn validate(&self, value: &Value) -> Vec<Violation> {
        let mut out = Vec::new();
        self.walk(&self.root, value, "", 0, &mut out);
        out
    }

    pub fn is_valid(&self, value: &Value) -> bool {
        self.validate(value).is_empty()
    }

    fn resolve(&self, r: &str) -> Option<&Value> {
        if r == "#" {
            return Some(&self.root);
        }
        let ptr = r.strip_prefix('#')?;
        self.root.pointer(ptr)
    }

    #[allow(
        clippy::too_many_lines,
        reason = "one match arm per keyword reads better than a dispatch table here"
    )]
    fn walk(
        &self,
        schema: &Value,
        value: &Value,
        path: &str,
        depth: usize,
        out: &mut Vec<Violation>,
    ) {
        let err = |out: &mut Vec<Violation>, message: String| {
            out.push(Violation {
                path: path.to_owned(),
                message,
            });
        };
        if depth > MAX_DEPTH {
            err(out, "schema recursion too deep".into());
            return;
        }
        let obj: &Map<String, Value> = match schema {
            Value::Bool(false) => {
                err(out, "no value is allowed here".into());
                return;
            }
            Value::Object(o) => o,
            // `true` and anything that is not a schema accept everything.
            _ => return,
        };
        if let Some(Value::String(r)) = obj.get("$ref") {
            match self.resolve(r) {
                Some(target) => self.walk(target, value, path, depth + 1, out),
                None => err(out, format!("unresolved reference {r}")),
            }
        }
        if let Some(t) = obj.get("type") {
            let types: Vec<&str> = match t {
                Value::String(s) => vec![s.as_str()],
                Value::Array(a) => a.iter().filter_map(Value::as_str).collect(),
                _ => Vec::new(),
            };
            if !types.iter().any(|t| type_matches(t, value)) {
                err(
                    out,
                    format!("expected {}, got {}", types.join(" or "), type_name(value)),
                );
                return;
            }
        }
        if let Some(Value::Array(options)) = obj.get("enum") {
            if !options.contains(value) {
                err(
                    out,
                    format!("must be one of {}", Value::Array(options.clone())),
                );
            }
        }
        if let Some(c) = obj.get("const") {
            if c != value {
                err(out, format!("must be {c}"));
            }
        }
        match value {
            Value::String(s) => Self::string_checks(obj, s, path, out),
            Value::Number(n) => {
                let x = n.as_f64().unwrap_or(f64::NAN);
                let bound = |k: &str| obj.get(k).and_then(Value::as_f64);
                if let Some(m) = bound("minimum") {
                    if x < m {
                        err(out, format!("must be at least {m}"));
                    }
                }
                if let Some(m) = bound("maximum") {
                    if x > m {
                        err(out, format!("must be at most {m}"));
                    }
                }
                if let Some(m) = bound("exclusiveMinimum") {
                    if x <= m {
                        err(out, format!("must be more than {m}"));
                    }
                }
                if let Some(m) = bound("exclusiveMaximum") {
                    if x >= m {
                        err(out, format!("must be less than {m}"));
                    }
                }
            }
            Value::Array(items) => {
                let count = |k: &str| obj.get(k).and_then(Value::as_u64);
                let len = items.len() as u64;
                if let Some(m) = count("minItems") {
                    if len < m {
                        err(out, format!("needs at least {m} items"));
                    }
                }
                if let Some(m) = count("maxItems") {
                    if len > m {
                        err(out, format!("allows at most {m} items"));
                    }
                }
                if obj.get("uniqueItems") == Some(&Value::Bool(true)) {
                    for (i, a) in items.iter().enumerate() {
                        if items[..i].contains(a) {
                            err(out, format!("item {i} is a duplicate"));
                        }
                    }
                }
                if let Some(item_schema) = obj.get("items") {
                    for (i, item) in items.iter().enumerate() {
                        self.walk(item_schema, item, &format!("{path}/{i}"), depth + 1, out);
                    }
                }
            }
            Value::Object(map) => {
                let props = obj.get("properties").and_then(Value::as_object);
                if let Some(Value::Array(req)) = obj.get("required") {
                    for r in req.iter().filter_map(Value::as_str) {
                        if !map.contains_key(r) {
                            err(out, format!("missing required property {r}"));
                        }
                    }
                }
                for (k, v) in map {
                    let child = format!("{path}/{}", escape_pointer(k));
                    if let Some(sub) = props.and_then(|p| p.get(k)) {
                        self.walk(sub, v, &child, depth + 1, out);
                    } else if let Some(extra) = obj.get("additionalProperties") {
                        if extra == &Value::Bool(false) {
                            out.push(Violation {
                                path: child,
                                message: "unexpected property".into(),
                            });
                        } else {
                            self.walk(extra, v, &child, depth + 1, out);
                        }
                    }
                }
            }
            _ => {}
        }
        if let Some(Value::Array(all)) = obj.get("allOf") {
            for sub in all {
                self.walk(sub, value, path, depth + 1, out);
            }
        }
        if let Some(Value::Array(any)) = obj.get("anyOf") {
            if !any.iter().any(|s| self.passes(s, value, depth)) {
                err(out, "matches none of the allowed shapes (anyOf)".into());
            }
        }
        if let Some(Value::Array(one)) = obj.get("oneOf") {
            let n = one.iter().filter(|s| self.passes(s, value, depth)).count();
            if n != 1 {
                err(
                    out,
                    format!("must match exactly one shape (oneOf), matched {n}"),
                );
            }
        }
        if let Some(not) = obj.get("not") {
            if self.passes(not, value, depth) {
                err(out, "matches a forbidden shape (not)".into());
            }
        }
    }

    fn passes(&self, schema: &Value, value: &Value, depth: usize) -> bool {
        let mut v = Vec::new();
        self.walk(schema, value, "", depth + 1, &mut v);
        v.is_empty()
    }

    fn string_checks(obj: &Map<String, Value>, s: &str, path: &str, out: &mut Vec<Violation>) {
        let mut err = |message: String| {
            out.push(Violation {
                path: path.to_owned(),
                message,
            });
        };
        let chars = s.chars().count() as u64;
        if let Some(m) = obj.get("minLength").and_then(Value::as_u64) {
            if chars < m {
                err(format!("must be at least {m} characters"));
            }
        }
        if let Some(m) = obj.get("maxLength").and_then(Value::as_u64) {
            if chars > m {
                err(format!("must be at most {m} characters"));
            }
        }
        if let Some(Value::String(p)) = obj.get("pattern") {
            // Compiled in check_schema, so this cannot fail for a schema
            // built through Validator::new.
            if let Ok(re) = Regex::new(p) {
                if !re.is_match(s) {
                    err(format!("does not match {p}"));
                }
            }
        }
        if let Some(Value::String(f)) = obj.get("format") {
            if !format_ok(f, s) {
                err(format!("is not a valid {f}"));
            }
        }
    }
}

fn format_ok(format: &str, s: &str) -> bool {
    use time::format_description::well_known::Rfc3339;
    match format {
        "date-time" => time::OffsetDateTime::parse(s, &Rfc3339).is_ok(),
        "date" => {
            let fd = time::macros::format_description!("[year]-[month]-[day]");
            time::Date::parse(s, &fd).is_ok()
        }
        "time" => {
            let short = time::macros::format_description!("[hour]:[minute]");
            let long = time::macros::format_description!("[hour]:[minute]:[second]");
            time::Time::parse(s, &short).is_ok() || time::Time::parse(s, &long).is_ok()
        }
        // Other formats are annotations, as the specification allows.
        _ => true,
    }
}

fn type_matches(t: &str, v: &Value) -> bool {
    match t {
        "string" => v.is_string(),
        "number" => v.is_number(),
        "integer" => match v {
            Value::Number(n) => {
                n.is_i64() || n.is_u64() || n.as_f64().is_some_and(|f| f.fract() == 0.0)
            }
            _ => false,
        },
        "boolean" => v.is_boolean(),
        "object" => v.is_object(),
        "array" => v.is_array(),
        "null" => v.is_null(),
        _ => false,
    }
}

fn type_name(v: &Value) -> &'static str {
    match v {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

fn escape_pointer(k: &str) -> String {
    k.replace('~', "~0").replace('/', "~1")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn v(schema: Value) -> Validator {
        Validator::new(schema).expect("valid schema")
    }

    #[test]
    fn objects_required_and_additional() {
        let s = v(json!({
            "type": "object",
            "properties": {
                "seconds": {"type": "integer", "minimum": 1, "maximum": 86400},
                "label": {"type": "string", "maxLength": 5}
            },
            "required": ["seconds"],
            "additionalProperties": false
        }));
        assert!(s.is_valid(&json!({"seconds": 60})));
        assert!(s.is_valid(&json!({"seconds": 60.0})));
        let errs = s.validate(&json!({"label": "toolong", "extra": 1}));
        let msgs: Vec<String> = errs.iter().map(ToString::to_string).collect();
        assert!(
            msgs.contains(&"/: missing required property seconds".to_owned()),
            "{msgs:?}"
        );
        assert!(
            msgs.contains(&"/label: must be at most 5 characters".to_owned()),
            "{msgs:?}"
        );
        assert!(
            msgs.contains(&"/extra: unexpected property".to_owned()),
            "{msgs:?}"
        );
        assert!(!s.is_valid(&json!({"seconds": 0})));
        assert!(!s.is_valid(&json!({"seconds": 1.5})));
        assert!(!s.is_valid(&json!({"seconds": "60"})));
        assert!(!s.is_valid(&json!([])));
    }

    #[test]
    fn enums_patterns_formats_arrays() {
        let s = v(json!({
            "type": "object",
            "properties": {
                "action": {"enum": ["play", "pause"]},
                "code": {"type": "string", "pattern": "^[A-Z]{3}$"},
                "at": {"type": "string", "format": "date-time"},
                "day": {"type": "string", "format": "date"},
                "tags": {"type": "array", "items": {"type": "string"}, "maxItems": 2, "uniqueItems": true}
            }
        }));
        assert!(s.is_valid(&json!({"action": "play", "code": "ABC",
            "at": "2026-10-02T09:00:00+03:00", "day": "2026-10-02", "tags": ["a", "b"]})));
        assert!(!s.is_valid(&json!({"action": "stop"})));
        assert!(!s.is_valid(&json!({"code": "abc"})));
        assert!(!s.is_valid(&json!({"at": "tomorrow"})));
        assert!(!s.is_valid(&json!({"day": "2026-13-01"})));
        assert!(!s.is_valid(&json!({"tags": ["a", "a"]})));
        assert!(!s.is_valid(&json!({"tags": ["a", "b", "c"]})));
        assert!(!s.is_valid(&json!({"tags": [1]})));
    }

    #[test]
    fn combinators_and_refs() {
        let s = v(json!({
            "$defs": {"id": {"type": "string", "minLength": 1}},
            "type": "object",
            "properties": {
                "target": {"oneOf": [{"$ref": "#/$defs/id"}, {"type": "integer"}]},
                "n": {"type": ["integer", "null"], "not": {"const": 13}}
            }
        }));
        assert!(s.is_valid(&json!({"target": "x", "n": null})));
        assert!(s.is_valid(&json!({"target": 4, "n": 12})));
        assert!(!s.is_valid(&json!({"target": ""})));
        assert!(!s.is_valid(&json!({"n": 13})));
        assert!(!s.is_valid(&json!({"n": "1"})));
    }

    #[test]
    fn refuses_schemas_it_cannot_enforce() {
        assert!(Validator::new(json!({"type": "object", "patternProperties": {}})).is_err());
        assert!(Validator::new(json!({"$ref": "https://example.org/s.json"})).is_err());
        assert!(Validator::new(json!({"pattern": "("})).is_err());
        assert!(Validator::new(json!(3)).is_err());
        assert!(Validator::new(json!(true)).is_ok());
    }

    #[test]
    fn self_reference_terminates() {
        let s = v(json!({"$ref": "#"}));
        assert!(!s.validate(&json!(1)).is_empty());
    }
}
