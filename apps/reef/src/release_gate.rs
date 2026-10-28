// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Release gate for placeholder and staging hosts. A release build sets
//! `--cfg release_build` (RUSTFLAGS), and then this module refuses to
//! compile while any shipped default contains `.example` (a placeholder
//! host) or the licence server names a staging host (a build-time
//! `REEF_LICENCE_SERVER` left over from a staging phone build).

// Without release_build, only the tests use these.
#![cfg_attr(
    not(release_build),
    allow(
        dead_code,
        reason = "used by the release_build assertion and the tests"
    )
)]

/// Byte-wise substring search, usable in a `const` context.
pub const fn contains(haystack: &str, needle: &str) -> bool {
    let (h, n) = (haystack.as_bytes(), needle.as_bytes());
    if n.len() > h.len() {
        return false;
    }
    let mut i = 0;
    while i + n.len() <= h.len() {
        let mut j = 0;
        while j < n.len() && h[i + j] == n[j] {
            j += 1;
        }
        if j == n.len() {
            return true;
        }
        i += 1;
    }
    false
}

/// Whether a shipped default still names a placeholder host.
pub const fn is_placeholder(value: &str) -> bool {
    contains(value, ".example")
}

/// The defaults that reach a phone when nothing overrides them.
pub const SHIPPED_DEFAULTS: &[&str] = &[
    crate::settings::DEFAULT_LICENCE_SERVER,
    reef_backend::repo::DEFAULT_URL_TEMPLATE,
];

const fn any_placeholder(values: &[&str]) -> bool {
    let mut i = 0;
    while i < values.len() {
        if is_placeholder(values[i]) {
            return true;
        }
        i += 1;
    }
    false
}

/// Whether a licence server names a staging host.
pub const fn is_staging(value: &str) -> bool {
    contains(value, "staging")
}

#[cfg(release_build)]
const _: () = assert!(
    !is_staging(crate::settings::DEFAULT_LICENCE_SERVER),
    "release build with a staging licence server: unset REEF_LICENCE_SERVER"
);

#[cfg(release_build)]
const _: () = assert!(
    !any_placeholder(SHIPPED_DEFAULTS),
    "release build with a placeholder .example host in settings::DEFAULT_LICENCE_SERVER \
     or reef_backend::repo::DEFAULT_URL_TEMPLATE: set the real hosts first"
);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_placeholders() {
        assert!(contains("https://reef.shipwright.example/x", ".example"));
        assert!(!contains("https://reefstore.app/x", ".example"));
        assert!(!contains("", ".example"));
        assert!(contains("abc", ""));
        assert!(is_placeholder("https://licences.shipwright.example"));
        assert!(any_placeholder(&[
            "https://reefstore.app/",
            "https://licences.shipwright.example"
        ]));
        assert!(!any_placeholder(&[]));
        // The shipped defaults are the production hosts, so a release build
        // passes this check.
        assert!(!any_placeholder(SHIPPED_DEFAULTS));
    }

    #[test]
    fn finds_staging_hosts() {
        assert!(is_staging("https://licences-staging.reefstore.app"));
        assert!(!is_staging("https://licences.reefstore.app"));
        if option_env!("REEF_LICENCE_SERVER").is_none_or(str::is_empty) {
            assert!(!is_staging(crate::settings::DEFAULT_LICENCE_SERVER));
        }
    }
}
