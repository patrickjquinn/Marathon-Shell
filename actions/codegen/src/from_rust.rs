// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Declarations from Rust sources: `#[keel::action]` functions,
//! `#[keel::entity]` and `#[keel::object]` structs.
//!
//! Types map as: `String` string; `bool` boolean; integer types integer
//! with their range (64-bit ones limited to ±(2^53 - 1), what JSON numbers
//! hold exactly); `f32`/`f64` number; `Option<T>` an optional `T`;
//! `Vec<T>` an array of `T`; `keel::EntityRef<T>` a reference to entity
//! `T` (`#[keel(entity = "<app-id>/<type>")]` for another app's);
//! `#[keel::object]` / `#[keel::entity]` structs objects. Field names are
//! used as they are (no serde renames).

use std::collections::HashMap;

use keel_actions_schema::decl::{Action, Entity, Param};
use serde_json::{json, Value};
use syn::{
    Attribute, Expr, ExprLit, Fields, FnArg, GenericArgument, Item, Lit, Pat, PathArguments,
    ReturnType, Type,
};

use crate::Diagnostics;

/// A struct the macros mark, by name.
#[derive(Clone)]
struct Record {
    entity_type: Option<String>,
    title: Option<String>,
    description: Option<String>,
    fields: Vec<(String, Type, Vec<Attribute>)>,
    source: String,
}

/// Rust declarations of a crate.
#[derive(Default, Debug)]
pub struct Found {
    pub actions: Vec<Action>,
    pub entities: Vec<Entity>,
}

fn is_keel_attr(attr: &Attribute, name: &str) -> bool {
    let segments: Vec<String> = attr
        .path()
        .segments
        .iter()
        .map(|s| s.ident.to_string())
        .collect();
    segments == ["keel", name]
}

fn lit_value(expr: &Expr) -> Option<Value> {
    match expr {
        Expr::Lit(ExprLit { lit, .. }) => match lit {
            Lit::Str(s) => Some(json!(s.value())),
            Lit::Bool(b) => Some(json!(b.value)),
            Lit::Int(i) => i.base10_parse::<i64>().ok().map(|v| json!(v)),
            Lit::Float(f) => f.base10_parse::<f64>().ok().map(|v| json!(v)),
            _ => None,
        },
        Expr::Unary(u) if matches!(u.op, syn::UnOp::Neg(_)) => {
            let v = lit_value(&u.expr)?;
            v.as_i64()
                .map(|i| json!(-i))
                .or_else(|| v.as_f64().map(|f| json!(-f)))
        }
        Expr::Array(a) => a
            .elems
            .iter()
            .map(lit_value)
            .collect::<Option<Vec<_>>>()
            .map(Value::Array),
        _ => None,
    }
}

/// `key = literal` and bare `flag` pairs of an attribute.
fn attr_args(attr: &Attribute) -> syn::Result<Vec<(String, Value)>> {
    let mut out = Vec::new();
    if matches!(attr.meta, syn::Meta::Path(_)) {
        return Ok(out);
    }
    attr.parse_nested_meta(|meta| {
        let key = meta
            .path
            .get_ident()
            .map(ToString::to_string)
            .unwrap_or_default();
        if meta.input.peek(syn::Token![=]) {
            let expr: Expr = meta.value()?.parse()?;
            let value =
                lit_value(&expr).ok_or_else(|| meta.error(format!("`{key}` must be a literal")))?;
            out.push((key, value));
        } else {
            out.push((key, json!(true)));
        }
        Ok(())
    })?;
    Ok(out)
}

fn last_segment(ty: &Type) -> Option<(&syn::Ident, Vec<&Type>)> {
    let Type::Path(p) = ty else { return None };
    let seg = p.path.segments.last()?;
    let args = match &seg.arguments {
        PathArguments::AngleBracketed(a) => a
            .args
            .iter()
            .filter_map(|g| match g {
                GenericArgument::Type(t) => Some(t),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    };
    Some((&seg.ident, args))
}

struct Reader<'a> {
    records: HashMap<String, Record>,
    diag: &'a mut Diagnostics,
}

const INT_SAFE: i64 = 9_007_199_254_740_991;

impl Reader<'_> {
    fn apply_attrs(&mut self, p: &mut Param, attrs: &[Attribute], at: &str) {
        for attr in attrs.iter().filter(|a| a.path().is_ident("keel")) {
            let args = match attr_args(attr) {
                Ok(a) => a,
                Err(e) => {
                    self.diag.error(at.to_owned(), e.to_string());
                    continue;
                }
            };
            for (key, value) in args {
                match key.as_str() {
                    "max_length" => p.max_length = value.as_u64(),
                    "min_length" => p.min_length = value.as_u64(),
                    "max_items" => p.max_items = value.as_u64(),
                    "minimum" => p.minimum = Some(value),
                    "maximum" => p.maximum = Some(value),
                    "pattern" => p.pattern = value.as_str().map(ToOwned::to_owned),
                    "format" => p.format = value.as_str().map(ToOwned::to_owned),
                    "description" => p.description = value.as_str().map(ToOwned::to_owned),
                    "title" => p.title = value.as_str().map(ToOwned::to_owned),
                    "entity" => p.entity = value.as_str().map(ToOwned::to_owned),
                    "values" => p.values = value.as_array().cloned().unwrap_or_default(),
                    "summarisable" => p.summarisable = value.as_bool().unwrap_or(false),
                    "indexable" => p.indexable = value.as_bool().unwrap_or(false),
                    other => self
                        .diag
                        .error(at.to_owned(), format!("unknown #[keel] key `{other}`")),
                }
            }
        }
    }

    /// The Param for a type, and whether it is required.
    fn param(
        &mut self,
        name: &str,
        ty: &Type,
        attrs: &[Attribute],
        at: &str,
        depth: usize,
    ) -> Option<(Param, bool)> {
        if depth > 6 {
            self.diag.error(at.to_owned(), "types nest too deeply");
            return None;
        }
        let Some((ident, args)) = last_segment(ty) else {
            self.diag.error(
                at.to_owned(),
                format!("`{name}`: unsupported type (references, tuples and slices are not)"),
            );
            return None;
        };
        let ident = ident.to_string();
        let mut p = Param::new(name, "string");
        let int = |lo: i64, hi: i64| (json!(lo), json!(hi));
        let range = match ident.as_str() {
            "i8" => Some(int(i64::from(i8::MIN), i64::from(i8::MAX))),
            "i16" => Some(int(i64::from(i16::MIN), i64::from(i16::MAX))),
            "i32" => Some(int(i64::from(i32::MIN), i64::from(i32::MAX))),
            "i64" | "isize" => Some(int(-INT_SAFE, INT_SAFE)),
            "u8" => Some(int(0, i64::from(u8::MAX))),
            "u16" => Some(int(0, i64::from(u16::MAX))),
            "u32" => Some(int(0, i64::from(u32::MAX))),
            "u64" | "usize" => Some(int(0, INT_SAFE)),
            _ => None,
        };
        match ident.as_str() {
            "Option" if args.len() == 1 => {
                let (p, _) = self.param(name, args[0], attrs, at, depth + 1)?;
                return Some((p, false));
            }
            "Vec" if args.len() == 1 => {
                let (inner, _) = self.param(name, args[0], &[], at, depth + 1)?;
                if inner.ty == "array" {
                    self.diag.error(
                        at.to_owned(),
                        format!("`{name}`: arrays of arrays are not supported"),
                    );
                    return None;
                }
                p = Param {
                    ty: "array".into(),
                    item_type: Some(inner.ty.clone()),
                    ..inner
                };
            }
            "String" => {}
            "bool" => p.ty = "boolean".into(),
            "f32" | "f64" => p.ty = "number".into(),
            _ if range.is_some() => {
                let (lo, hi) = range.unwrap_or_default();
                p.ty = "integer".into();
                p.minimum = Some(lo);
                p.maximum = Some(hi);
            }
            "EntityRef" => {
                p.ty = "entity".into();
                if let Some(target) = args
                    .first()
                    .and_then(|t| last_segment(t))
                    .map(|(i, _)| i.to_string())
                {
                    if target != "Any" {
                        match self.records.get(&target).and_then(|r| r.entity_type.clone()) {
                            Some(t) => p.entity = Some(t),
                            None => self.diag.error(
                                at.to_owned(),
                                format!("`{name}`: {target} is not a #[keel::entity] struct of this crate"),
                            ),
                        }
                    }
                }
            }
            other => {
                let Some(record) = self.records.get(other).cloned() else {
                    self.diag.error(
                        at.to_owned(),
                        format!("`{name}`: type {other} is not supported; use String, bool, integers, f64, Option, Vec, keel::EntityRef or a #[keel::object] struct"),
                    );
                    return None;
                };
                p.ty = "object".into();
                for (field, fty, fattrs) in &record.fields {
                    if let Some((fp, required)) =
                        self.param(field, fty, fattrs, &record.source, depth + 1)
                    {
                        p.properties.push(Param { required, ..fp });
                    }
                }
            }
        }
        self.apply_attrs(&mut p, attrs, at);
        let is_ref =
            p.ty == "entity" || (p.ty == "array" && p.item_type.as_deref() == Some("entity"));
        {
            if is_ref && p.entity.is_none() {
                self.diag.error(at.to_owned(), format!("`{name}`: EntityRef needs a type (EntityRef<Note>) or #[keel(entity = \"<app-id>/<type>\")]"));
            }
        }
        Some((p, true))
    }

    fn action(&mut self, f: &syn::ItemFn, attr: &Attribute, file: &str) -> Option<Action> {
        let at = format!("{file}:{}", f.sig.ident.span().start().line);
        let mut a = Action {
            source: at.clone(),
            native: true,
            ..Action::default()
        };
        let args = match attr_args(attr) {
            Ok(a) => a,
            Err(e) => {
                self.diag.error(at, e.to_string());
                return None;
            }
        };
        for (key, value) in args {
            let s = || value.as_str().map(ToOwned::to_owned);
            let b = value.as_bool().unwrap_or(false);
            match key.as_str() {
                "name" => a.name = s().unwrap_or_default(),
                "title" => a.title = s(),
                "description" => a.description = s().unwrap_or_default(),
                "read_only" => a.read_only = b,
                "destructive" => a.destructive = b,
                "idempotent" => a.idempotent = b,
                "open_world" => a.open_world = b,
                "confirm" => a.confirm = b,
                "sensitive" => a.sensitive = b,
                "untrusted" => a.untrusted = b,
                "not_destructive_because" => a.not_destructive_because = s(),
                "timeout_ms" => a.timeout_ms = value.as_u64().unwrap_or(25_000),
                other => self
                    .diag
                    .error(at.clone(), format!("unknown #[keel::action] key `{other}`")),
            }
        }
        for input in &f.sig.inputs {
            let FnArg::Typed(pt) = input else { continue };
            let Pat::Ident(ident) = &*pt.pat else {
                continue;
            };
            let name = ident.ident.to_string();
            if let Some((p, required)) = self.param(&name, &pt.ty, &pt.attrs, &at, 0) {
                a.params.push(Param { required, ..p });
            }
        }
        if let ReturnType::Type(_, ty) = &f.sig.output {
            let inner = match last_segment(ty) {
                Some((ident, args)) if ident == "Result" && !args.is_empty() => args[0],
                _ => {
                    self.diag
                        .error(at.clone(), "an action returns keel::Result<T> or nothing");
                    return None;
                }
            };
            let unit = matches!(inner, Type::Tuple(t) if t.elems.is_empty());
            if !unit {
                if let Some((p, _)) = self.param("", inner, &[], &at, 0) {
                    a.returns = Some(p);
                }
            }
        }
        Some(a)
    }

    fn entity(&mut self, name: &str) -> Option<Entity> {
        let record = self.records.get(name)?.clone();
        let type_name = record.entity_type.clone()?;
        let mut e = Entity {
            type_name,
            title: record.title.clone(),
            description: record.description.clone().unwrap_or_default(),
            source: record.source.clone(),
            native: true,
            ..Entity::default()
        };
        let mut has = (false, false);
        for (field, ty, attrs) in &record.fields {
            match field.as_str() {
                "id" => has.0 = true,
                "title" => has.1 = true,
                _ => {
                    if let Some((p, required)) = self.param(field, ty, attrs, &record.source, 0) {
                        e.properties.push(Param { required, ..p });
                    }
                }
            }
        }
        if !(has.0 && has.1) {
            self.diag.error(
                record.source,
                format!("#[keel::entity] {name} needs `id: String` and `title: String` fields"),
            );
        }
        Some(e)
    }
}

fn collect_items<'a>(items: &'a [Item], out: &mut Vec<&'a Item>) {
    for item in items {
        if let Item::Mod(m) = item {
            if let Some((_, inner)) = &m.content {
                collect_items(inner, out);
            }
        }
        out.push(item);
    }
}

/// Reads `#[keel::...]` declarations from parsed files (`(name, file)`).
pub fn read(files: &[(String, syn::File)], diag: &mut Diagnostics) -> Found {
    let mut reader = Reader {
        records: HashMap::new(),
        diag,
    };
    let mut all = Vec::new();
    for (name, file) in files {
        let mut items = Vec::new();
        collect_items(&file.items, &mut items);
        all.push((name, items));
    }
    let mut entity_order = Vec::new();
    for (file, items) in &all {
        for item in items {
            let Item::Struct(s) = item else { continue };
            let entity = s.attrs.iter().find(|a| is_keel_attr(a, "entity"));
            let object = s.attrs.iter().any(|a| is_keel_attr(a, "object"));
            if entity.is_none() && !object {
                continue;
            }
            let source = format!("{file}:{}", s.ident.span().start().line);
            let mut record = Record {
                entity_type: None,
                title: None,
                description: None,
                fields: Vec::new(),
                source: source.clone(),
            };
            if let Some(attr) = entity {
                match attr_args(attr) {
                    Ok(args) => {
                        for (k, v) in args {
                            let v = v.as_str().map(ToOwned::to_owned);
                            match k.as_str() {
                                "type" => record.entity_type = v,
                                "title" => record.title = v,
                                "description" => record.description = v,
                                _ => {}
                            }
                        }
                    }
                    Err(e) => reader.diag.error(source.clone(), e.to_string()),
                }
                entity_order.push(s.ident.to_string());
            }
            if let Fields::Named(named) = &s.fields {
                for f in &named.named {
                    if let Some(ident) = &f.ident {
                        record
                            .fields
                            .push((ident.to_string(), f.ty.clone(), f.attrs.clone()));
                    }
                }
            }
            reader.records.insert(s.ident.to_string(), record);
        }
    }
    let mut found = Found::default();
    for name in entity_order {
        if let Some(e) = reader.entity(&name) {
            found.entities.push(e);
        }
    }
    for (file, items) in &all {
        for item in items {
            let Item::Fn(f) = item else { continue };
            if let Some(attr) = f.attrs.iter().find(|a| is_keel_attr(a, "action")) {
                if let Some(a) = reader.action(f, attr, file) {
                    found.actions.push(a);
                }
            }
        }
    }
    found
}
