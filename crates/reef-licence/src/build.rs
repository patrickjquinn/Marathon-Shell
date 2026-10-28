// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Build-script helper that embeds the trusted licence keys (feature
//! `build`, used as a build-dependency).
//!
//! Every app that verifies licences exposes
//! `pub const EMBEDDED_KEYS: &[(&str, &str)]`. Its `build.rs` calls
//! [`embed_keys`], which reads `SHIPWRIGHT_LICENCE_KEYS`
//! (`kid:base64url[,kid:base64url...]`, the form the licence service's
//! `public-key` command prints and `PILOT_RELAY_LICENCE_KEYS` takes),
//! checks every key as [`KeySet::insert_text`] would at run time, and writes
//! the const's value to `$OUT_DIR/licence_keys.rs` for `include!`. Unset or
//! blank gives an empty set, which rejects every token.
//!
//! A release build (`--cfg release_build`, which cargo shows a build script
//! as `CARGO_CFG_RELEASE_BUILD`) refuses key ids starting with `staging` or
//! `test`, so a test key can never ship.

use std::fmt::Write as _;
use std::path::Path;

use crate::KeySet;

/// The build-time variable naming the keys to embed.
pub const ENV_VAR: &str = "SHIPWRIGHT_LICENCE_KEYS";
/// The file written into `OUT_DIR`.
pub const OUT_FILE: &str = "licence_keys.rs";
/// Key-id prefixes (compared ignoring ASCII case) refused in a release build.
pub const NON_RELEASE_PREFIXES: &[&str] = &["staging", "test"];

/// Parses `kid:base64url[,kid:base64url...]` strictly: every entry must be a
/// key [`KeySet::insert_text`] accepts (id of `[A-Za-z0-9._-]`, a 32-byte
/// unpadded base64url Ed25519 key that is a valid, non-weak point), with no
/// empty entries and no repeated key id. Blank input is an empty list.
pub fn parse_keys(value: &str) -> Result<Vec<(String, String)>, String> {
    if value.trim().is_empty() {
        return Ok(Vec::new());
    }
    let mut keys: Vec<(String, String)> = Vec::new();
    for (i, entry) in value.split(',').map(str::trim).enumerate() {
        let n = i + 1;
        if entry.is_empty() {
            return Err(format!("entry {n} is empty"));
        }
        KeySet::new()
            .insert_text(entry)
            .map_err(|e| format!("entry {n}: {e}"))?;
        // insert_text accepted it, so the split cannot fail.
        let (kid, b64) = entry.split_once(':').unwrap_or_default();
        if keys.iter().any(|(k, _)| k == kid) {
            return Err(format!("entry {n}: key id {kid:?} appears twice"));
        }
        keys.push((kid.to_string(), b64.to_string()));
    }
    Ok(keys)
}

/// Refuses key ids a release must not trust (see [`NON_RELEASE_PREFIXES`]).
pub fn check_release(keys: &[(String, String)]) -> Result<(), String> {
    for (kid, _) in keys {
        let lower = kid.to_ascii_lowercase();
        if let Some(p) = NON_RELEASE_PREFIXES.iter().find(|p| lower.starts_with(*p)) {
            return Err(format!(
                "key id {kid:?} starts with {p:?}: a test or staging key must not reach a \
                 release build (--cfg release_build)"
            ));
        }
    }
    Ok(())
}

/// The Rust expression `include!`d as the value of `EMBEDDED_KEYS`.
pub fn render(keys: &[(String, String)]) -> String {
    let mut out = String::from("&[\n");
    for (kid, b64) in keys {
        // Both are plain ASCII from a restricted alphabet; Debug quotes them.
        let _ = writeln!(out, "    ({kid:?}, {b64:?}),");
    }
    out.push(']');
    out
}

/// Parses and, for a release build, checks `value`; then renders it.
pub fn generate(value: &str, release: bool) -> Result<String, String> {
    let keys = parse_keys(value)?;
    if release {
        check_release(&keys)?;
    }
    Ok(render(&keys))
}

/// The whole build-script step: call it from `build.rs`, then
/// `include!(concat!(env!("OUT_DIR"), "/licence_keys.rs"))` as the value of
/// `EMBEDDED_KEYS`. Fails the build with the reason on a bad value.
///
/// # Panics
///
/// On a malformed `SHIPWRIGHT_LICENCE_KEYS`, a non-release key id in a
/// release build, or when `OUT_DIR` cannot be written. Panicking is how a
/// build script fails the build.
pub fn embed_keys() {
    println!("cargo:rerun-if-env-changed={ENV_VAR}");
    let value = match std::env::var(ENV_VAR) {
        Ok(v) => v,
        Err(std::env::VarError::NotPresent) => String::new(),
        Err(std::env::VarError::NotUnicode(_)) => panic!("{ENV_VAR} is not valid UTF-8"),
    };
    let release = std::env::var_os("CARGO_CFG_RELEASE_BUILD").is_some();
    let code = generate(&value, release)
        .unwrap_or_else(|e| panic!("{ENV_VAR} (expected kid:base64url[,kid:base64url...]): {e}"));
    let out_dir = std::env::var_os("OUT_DIR").expect("OUT_DIR is set for build scripts");
    let path = Path::new(&out_dir).join(OUT_FILE);
    std::fs::write(&path, code).unwrap_or_else(|e| panic!("writing {}: {e}", path.display()));
}

#[cfg(test)]
mod tests {
    use super::*;

    // A valid Ed25519 public key (the test signer's, seed [7; 32]).
    fn key() -> String {
        crate::testkeys::signer_a().public_key_text()
    }

    #[test]
    fn blank_is_empty() {
        assert_eq!(parse_keys("").unwrap(), Vec::new());
        assert_eq!(parse_keys("  \n").unwrap(), Vec::new());
        assert_eq!(generate("", true).unwrap(), "&[\n]");
    }

    #[test]
    fn parses_one_and_several() {
        let text = key();
        let (_, b64) = text.split_once(':').unwrap();
        let keys = parse_keys(&format!("k1:{b64}")).unwrap();
        assert_eq!(keys, vec![("k1".to_string(), b64.to_string())]);
        let keys = parse_keys(&format!(" k1:{b64} , k2.next:{b64} ")).unwrap();
        assert_eq!(keys.len(), 2);
        assert_eq!(keys[1].0, "k2.next");
    }

    #[test]
    fn rejects_malformed() {
        let text = key();
        let (_, b64) = text.split_once(':').unwrap();
        // No separator, empty entries, bad kid, bad base64, wrong length,
        // padding, repeated kid.
        for bad in [
            "k1".to_string(),
            format!("k1:{b64},"),
            format!(",k1:{b64}"),
            format!("k1:{b64},,k2:{b64}"),
            format!(":{b64}"),
            format!("k 1:{b64}"),
            format!("k/1:{b64}"),
            "k1:not*base64".to_string(),
            "k1:AAAA".to_string(),
            format!("k1:{b64}="),
            "k1:".to_string(),
            format!("k1:{b64},k1:{b64}"),
        ] {
            assert!(parse_keys(&bad).is_err(), "{bad:?} was accepted");
        }
    }

    #[test]
    fn release_refuses_test_and_staging_kids() {
        let text = key();
        let (_, b64) = text.split_once(':').unwrap();
        for kid in ["staging-k1", "test-a", "Staging", "TEST.x", "testing"] {
            let v = format!("prod-k1:{b64},{kid}:{b64}");
            assert!(
                generate(&v, false).is_ok(),
                "{kid} refused outside a release"
            );
            let e = generate(&v, true).unwrap_err();
            assert!(e.contains(kid), "{e}");
        }
        assert!(generate(&format!("prod-k1:{b64},k2-test:{b64}"), true).is_ok());
    }

    #[test]
    fn rendered_value_round_trips() {
        let text = key();
        let (_, b64) = text.split_once(':').unwrap();
        let code = generate(&format!("k1:{b64},k2:{b64}"), true).unwrap();
        assert_eq!(
            code,
            format!("&[\n    (\"k1\", \"{b64}\"),\n    (\"k2\", \"{b64}\"),\n]")
        );
    }
}
