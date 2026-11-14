// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Keel Actions' contract (ADR-0018), shared by the generator
//! (`keel-actions-codegen`), `keel-mcp` and Reef's review
//! (`reef/devportal-core`):
//!
//! - [`decl`]: the declaration model and the manifest (`actions.json`) it
//!   generates. The C++ runtime (`keel/actions/plugin`) builds the same
//!   manifest from live QML declarations; `keel_actions_describe_golden`
//!   checks that both agree.
//! - [`validate`]: the JSON Schema subset and its validator.
//! - [`example`]: a minimal valid value for a schema (test stubs, plans).
//! - [`review`]: the rules Reef applies to an uploaded manifest.
//! - [`plan`]: type-checked multi-step plans with entity references.

pub mod decl;
pub mod example;
pub mod plan;
pub mod review;
pub mod validate;

/// The `_meta` namespace of Keel's keys.
pub const META: &str = "org.shipwright.keel/";

/// `org.shipwright.keel/<name>`.
pub fn meta_key(name: &str) -> String {
    format!("{META}{name}")
}

/// Bounds of the schema subset.
pub mod bounds {
    pub const DEFAULT_MAX_LENGTH: u64 = 4096;
    pub const DEFAULT_MAX_ITEMS: u64 = 100;
    pub const DEFAULT_INT_MIN: i64 = -2_147_483_648;
    pub const DEFAULT_INT_MAX: i64 = 2_147_483_647;
    pub const MAX_LENGTH_LIMIT: u64 = 1_000_000;
    pub const MAX_ITEMS_LIMIT: u64 = 10_000;
    pub const MAX_DEPTH: usize = 4;
    pub const ID_MAX_LENGTH: u64 = 256;
    pub const TITLE_MAX_LENGTH: u64 = 512;
    pub const CONTEXT_TEXT_MAX_LENGTH: u64 = 4000;
    pub const CONTEXT_PURPOSE_MAX_LENGTH: u64 = 200;
    pub const FIND_QUERY_MAX_LENGTH: u64 = 256;
    pub const FIND_LIMIT_MAX: u64 = 50;
    pub const DEFAULT_TIMEOUT_MS: u64 = 25_000;
    pub const DESCRIPTION_MIN: usize = 20;
    pub const DESCRIPTION_MAX: usize = 1024;
    pub const TOOL_NAME_MAX: usize = 128;
}

/// Backslash before the regex metacharacters `\.+*?()|[]{}^$-`, as the C++
/// runtime does, so both write identical patterns.
pub fn escape_regex(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 8);
    for c in text.chars() {
        if "\\.+*?()|[]{}^$-".contains(c) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// Is `id` an app ID: dot-separated segments of `[A-Za-z0-9_-]`, at least
/// two, at most 255 characters (a D-Bus well-known name).
pub fn is_app_id(id: &str) -> bool {
    id.len() <= 255
        && id.split('.').count() >= 2
        && id.split('.').all(|s| {
            !s.is_empty()
                && !s.starts_with(|c: char| c.is_ascii_digit())
                && s.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        })
}

/// Is `name` an action name: `domain.verb`, dot-separated lower-case words.
pub fn is_action_name(name: &str) -> bool {
    name.len() <= 64 && name.split('.').count() >= 2 && name.split('.').all(is_word)
}

/// Is `name` an entity type or shortcut word: a lower-case word
/// (`[a-z][a-z0-9_]*`; shortcuts may also use `-`).
pub fn is_word(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert!(is_app_id("org.shipwright.shoal-keys"));
        assert!(!is_app_id("keys"));
        assert!(!is_app_id("org..x"));
        assert!(is_action_name("notes.create"));
        assert!(!is_action_name("Notes.create"));
        assert!(!is_action_name("create"));
        assert_eq!(escape_regex("org.a-b/x"), "org\\.a\\-b/x");
    }
}
