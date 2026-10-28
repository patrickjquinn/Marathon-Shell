// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The attribute macros behind `#[keel::action]`, `#[keel::entity]` and
//! `#[keel::object]` (ADR-0018). Apps use them through the `keel` crate.
//!
//! The macros only register functions for dispatch and strip Keel's helper
//! attributes (`#[keel(...)]` on parameters and fields). The schemas are
//! written by the generator (`keel actions`), which reads the same source;
//! the macros check here what the generator relies on (a name, a
//! description, owned parameter types), so mistakes fail at compile time.

use proc_macro::TokenStream;
use proc_macro2::{Span, TokenStream as TokenStream2};
use quote::{format_ident, quote};
use syn::{
    parse_macro_input, spanned::Spanned, Attribute, Error, Expr, ExprLit, FnArg, ItemFn,
    ItemStruct, Lit, LitStr, Pat, Type,
};

/// Declares a Keel action. See the `keel` crate.
#[proc_macro_attribute]
pub fn action(attr: TokenStream, item: TokenStream) -> TokenStream {
    let mut function = parse_macro_input!(item as ItemFn);
    match expand_action(attr.into(), &mut function) {
        Ok(tokens) => tokens.into(),
        Err(error) => {
            let error = error.to_compile_error();
            strip_param_attrs(&mut function);
            quote!(#function #error).into()
        }
    }
}

/// Declares a Keel entity type. See the `keel` crate.
#[proc_macro_attribute]
pub fn entity(attr: TokenStream, item: TokenStream) -> TokenStream {
    let mut item = parse_macro_input!(item as ItemStruct);
    match expand_entity(attr.into(), &mut item) {
        Ok(tokens) => tokens.into(),
        Err(error) => {
            let error = error.to_compile_error();
            strip_field_attrs(&mut item);
            quote!(#item #error).into()
        }
    }
}

/// Declares a record type used in action parameters or results (fields may
/// carry `#[keel(...)]` bounds). See the `keel` crate.
#[proc_macro_attribute]
pub fn object(attr: TokenStream, item: TokenStream) -> TokenStream {
    let mut item = parse_macro_input!(item as ItemStruct);
    let attr: TokenStream2 = attr.into();
    let error = if attr.is_empty() {
        None
    } else {
        Some(Error::new(attr.span(), "#[keel::object] takes no arguments").to_compile_error())
    };
    let checks = check_field_attrs(&item);
    strip_field_attrs(&mut item);
    quote!(#item #error #checks).into()
}

/// Keys the generator understands in `#[keel::action(...)]`.
const ACTION_FLAGS: &[&str] = &[
    "read_only",
    "destructive",
    "idempotent",
    "open_world",
    "confirm",
    "sensitive",
    "untrusted",
];
const ACTION_STRINGS: &[&str] = &["name", "title", "description", "not_destructive_because"];
const ACTION_INTS: &[&str] = &["timeout_ms"];
/// Keys of `#[keel(...)]` on parameters and fields.
const PARAM_KEYS: &[&str] = &[
    "max_length",
    "min_length",
    "max_items",
    "minimum",
    "maximum",
    "pattern",
    "format",
    "description",
    "title",
    "entity",
    "values",
    "summarisable",
    "indexable",
];

struct ActionArgs {
    name: Option<LitStr>,
    description: Option<LitStr>,
}

fn parse_action_args(attr: TokenStream2) -> syn::Result<ActionArgs> {
    let mut args = ActionArgs {
        name: None,
        description: None,
    };
    let parser = syn::meta::parser(|meta| {
        let key = meta
            .path
            .get_ident()
            .map(ToString::to_string)
            .unwrap_or_default();
        if ACTION_FLAGS.contains(&key.as_str()) {
            if meta.input.peek(syn::Token![=]) {
                let _: syn::LitBool = meta.value()?.parse()?;
            }
            Ok(())
        } else if ACTION_STRINGS.contains(&key.as_str()) {
            let value: LitStr = meta.value()?.parse()?;
            match key.as_str() {
                "name" => args.name = Some(value),
                "description" => args.description = Some(value),
                _ => {}
            }
            Ok(())
        } else if ACTION_INTS.contains(&key.as_str()) {
            let _: syn::LitInt = meta.value()?.parse()?;
            Ok(())
        } else {
            Err(meta.error(format!(
                "unknown key `{key}`; expected one of: {}",
                [ACTION_STRINGS, ACTION_FLAGS, ACTION_INTS]
                    .concat()
                    .join(", ")
            )))
        }
    });
    syn::parse::Parser::parse2(parser, attr)?;
    Ok(args)
}

fn check_action_name(name: &LitStr) -> syn::Result<()> {
    let value = name.value();
    let ok = value.len() <= 64
        && value.split('.').count() >= 2
        && value.split('.').all(|part| {
            let mut chars = part.chars();
            chars.next().is_some_and(|c| c.is_ascii_lowercase())
                && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
        });
    if ok {
        Ok(())
    } else {
        Err(Error::new(
            name.span(),
            "an action name is `domain.verb`: dot-separated lower-case words (a-z, 0-9, _), at most 64 characters",
        ))
    }
}

fn is_keel_attr(attr: &Attribute) -> bool {
    attr.path().is_ident("keel")
}

fn check_keel_attr(attr: &Attribute) -> syn::Result<()> {
    attr.parse_nested_meta(|meta| {
        let key = meta
            .path
            .get_ident()
            .map(ToString::to_string)
            .unwrap_or_default();
        if !PARAM_KEYS.contains(&key.as_str()) {
            return Err(meta.error(format!(
                "unknown key `{key}`; expected one of: {}",
                PARAM_KEYS.join(", ")
            )));
        }
        if meta.input.peek(syn::Token![=]) {
            let _: Expr = meta.value()?.parse()?;
        }
        Ok(())
    })
}

fn strip_param_attrs(function: &mut ItemFn) {
    for input in &mut function.sig.inputs {
        if let FnArg::Typed(pat) = input {
            pat.attrs.retain(|a| !is_keel_attr(a));
        }
    }
}

fn check_field_attrs(item: &ItemStruct) -> TokenStream2 {
    let mut errors = TokenStream2::new();
    for field in &item.fields {
        for attr in field.attrs.iter().filter(|a| is_keel_attr(a)) {
            if let Err(e) = check_keel_attr(attr) {
                errors.extend(e.to_compile_error());
            }
        }
    }
    errors
}

fn strip_field_attrs(item: &mut ItemStruct) {
    for field in &mut item.fields {
        field.attrs.retain(|a| !is_keel_attr(a));
    }
}

fn is_reference(ty: &Type) -> bool {
    match ty {
        Type::Reference(_) => true,
        Type::Group(g) => is_reference(&g.elem),
        Type::Paren(p) => is_reference(&p.elem),
        _ => false,
    }
}

fn expand_action(attr: TokenStream2, function: &mut ItemFn) -> syn::Result<TokenStream2> {
    let args = parse_action_args(attr)?;
    let name = args.name.ok_or_else(|| {
        Error::new(
            Span::call_site(),
            "#[keel::action] needs `name = \"domain.verb\"`",
        )
    })?;
    check_action_name(&name)?;
    let description = args.description.ok_or_else(|| {
        Error::new(
            Span::call_site(),
            "#[keel::action] needs `description = \"...\"`: it is what a model reads to choose the action",
        )
    })?;
    if description.value().trim().len() < 20 {
        return Err(Error::new(
            description.span(),
            "the description must say what the action does (at least 20 characters)",
        ));
    }
    if function.sig.generics.lt_token.is_some() {
        return Err(Error::new(
            function.sig.generics.span(),
            "a Keel action cannot be generic",
        ));
    }

    let mut fields = Vec::new();
    let mut names = Vec::new();
    for input in &function.sig.inputs {
        let FnArg::Typed(pat) = input else {
            return Err(Error::new(
                input.span(),
                "a Keel action is a free function, not a method",
            ));
        };
        let Pat::Ident(ident) = &*pat.pat else {
            return Err(Error::new(
                pat.pat.span(),
                "Keel action parameters must be plain names",
            ));
        };
        if is_reference(&pat.ty) {
            return Err(Error::new(
                pat.ty.span(),
                "Keel action parameters must be owned types (String, not &str)",
            ));
        }
        for attr in pat.attrs.iter().filter(|a| is_keel_attr(a)) {
            check_keel_attr(attr)?;
        }
        let ident = &ident.ident;
        let ty = &pat.ty;
        fields.push(quote!(#ident: #ty));
        names.push(ident.clone());
    }
    strip_param_attrs(function);
    // Parameters are owned by design (they are decoded from JSON).
    function
        .attrs
        .push(syn::parse_quote!(#[allow(clippy::needless_pass_by_value)]));
    // The return type is fixed (keel::Result<T>), even when it cannot fail.
    function
        .attrs
        .push(syn::parse_quote!(#[allow(clippy::unnecessary_wraps)]));

    let fn_name = &function.sig.ident;
    let wrapper = format_ident!("__keel_action_{}", fn_name);
    let call = if function.sig.asyncness.is_some() {
        quote! {
            ::keel::Invocation::future(async move {
                ::keel::IntoReply::into_reply(#fn_name(#(args.#names),*).await)
            })
        }
    } else {
        quote! {
            ::keel::Invocation::ready(::keel::IntoReply::into_reply(#fn_name(#(args.#names),*)))
        }
    };

    Ok(quote! {
        #function

        #[doc(hidden)]
        #[allow(non_snake_case, clippy::needless_pass_by_value)]
        fn #wrapper(value: ::keel::__private::Value) -> ::keel::Invocation {
            #[derive(::keel::__private::Deserialize)]
            #[serde(crate = "::keel::__private::serde", deny_unknown_fields)]
            struct Args { #(#fields),* }
            let args: Args = match ::keel::__private::from_value(value) {
                Ok(args) => args,
                Err(error) => return ::keel::Invocation::ready(Err(::keel::Error::invalid_arguments(error.to_string()))),
            };
            #call
        }

        ::keel::__private::inventory::submit! {
            ::keel::NativeAction { name: #name, invoke: #wrapper }
        }
    })
}

fn string_arg(value: &Expr) -> Option<String> {
    match value {
        Expr::Lit(ExprLit {
            lit: Lit::Str(s), ..
        }) => Some(s.value()),
        _ => None,
    }
}

fn expand_entity(attr: TokenStream2, item: &mut ItemStruct) -> syn::Result<TokenStream2> {
    let mut type_name: Option<LitStr> = None;
    let parser = syn::meta::parser(|meta| {
        let key = meta
            .path
            .get_ident()
            .map(ToString::to_string)
            .unwrap_or_default();
        match key.as_str() {
            "type" => {
                type_name = Some(meta.value()?.parse()?);
                Ok(())
            }
            "title" | "description" => {
                let value: Expr = meta.value()?.parse()?;
                if string_arg(&value).is_none() {
                    return Err(Error::new(value.span(), "expected a string literal"));
                }
                Ok(())
            }
            _ => Err(meta.error(format!(
                "unknown key `{key}`; expected type, title, description"
            ))),
        }
    });
    syn::parse::Parser::parse2(parser, attr)?;
    let type_name = type_name
        .ok_or_else(|| Error::new(Span::call_site(), "#[keel::entity] needs `type = \"name\"`"))?;
    let value = type_name.value();
    let valid = value.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && value
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
        && value.len() <= 32;
    if !valid {
        return Err(Error::new(
            type_name.span(),
            "an entity type is one lower-case word (a-z, 0-9, _), at most 32 characters",
        ));
    }
    for field in &item.fields {
        for attr in field.attrs.iter().filter(|a| is_keel_attr(a)) {
            check_keel_attr(attr)?;
        }
    }
    strip_field_attrs(item);
    let ident = &item.ident;
    let get = format_ident!("__keel_entity_get_{}", ident);
    let find = format_ident!("__keel_entity_find_{}", ident);
    Ok(quote! {
        #item

        impl ::keel::Entity for #ident {
            const TYPE: &'static str = #type_name;
        }

        #[doc(hidden)]
        #[allow(non_snake_case)]
        fn #get(id: &str) -> ::keel::Result<Option<::keel::__private::Value>> {
            match <#ident as ::keel::EntitySource>::get(id)? {
                Some(entity) => ::keel::__private::to_value(&entity).map(Some).map_err(::keel::Error::failed),
                None => Ok(None),
            }
        }

        #[doc(hidden)]
        #[allow(non_snake_case)]
        fn #find(query: &str, limit: u32) -> ::keel::Result<Vec<::keel::__private::Value>> {
            <#ident as ::keel::EntitySource>::find(query, limit)?
                .iter()
                .map(|entity| ::keel::__private::to_value(entity).map_err(::keel::Error::failed))
                .collect()
        }

        ::keel::__private::inventory::submit! {
            ::keel::NativeEntity { type_name: #type_name, get: #get, find: #find }
        }
    })
}
