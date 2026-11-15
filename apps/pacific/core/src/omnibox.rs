// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! What the person typed in the address bar: an address to open or words
//! to search for.

use serde::Serialize;

use crate::search::SearchEngine;

/// The outcome of classifying address-bar input.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Navigation {
    /// Open this URL.
    Url { url: String },
    /// Search `query` with the engine `engine` (its results page is `url`).
    Search {
        engine: String,
        query: String,
        url: String,
    },
}

impl Navigation {
    pub fn url(&self) -> &str {
        match self {
            Self::Url { url } | Self::Search { url, .. } => url,
        }
    }
}

/// Schemes the address bar opens as they are.
const PASSTHROUGH: &[&str] = &["http", "https", "about", "file", "view-source"];

/// Classifies `input`. `keyword` looks up an engine by its keyword (the
/// first word of `w rust`); `default` is the default engine. `None` for
/// empty input.
pub fn classify(
    input: &str,
    default: &SearchEngine,
    keyword: &dyn Fn(&str) -> Option<SearchEngine>,
) -> Option<Navigation> {
    let text = input.trim();
    if text.is_empty() {
        return None;
    }
    let search = |engine: &SearchEngine, q: &str| Navigation::Search {
        engine: engine.id.clone(),
        query: q.to_owned(),
        url: engine.search_url_for(q),
    };
    // "?words" always searches.
    if let Some(q) = text.strip_prefix('?') {
        let q = q.trim();
        return (!q.is_empty()).then(|| search(default, q));
    }
    if let Some((first, rest)) = text.split_once(char::is_whitespace) {
        if let Some(engine) = keyword(first) {
            let rest = rest.trim();
            if !rest.is_empty() {
                return Some(search(&engine, rest));
            }
        }
    }
    if let Some(url) = as_url(text) {
        return Some(Navigation::Url { url });
    }
    Some(search(default, text))
}

/// `text` as an address, if it is one: a URL with a scheme Pacific opens,
/// `localhost`, an IP address, or a host whose last label is a public
/// suffix (`example.com`, `bbc.co.uk/news`). Hosts get `https://` (the
/// HTTPS-first policy falls back when a site has no HTTPS); `localhost`,
/// IP addresses and `.local` names get `http://`.
#[allow(
    clippy::case_sensitive_file_extension_comparisons,
    reason = "host suffixes, lower-cased first"
)]
pub fn as_url(text: &str) -> Option<String> {
    if text.chars().any(char::is_whitespace) {
        return None;
    }
    if let Some((scheme, _)) = text.split_once(':') {
        let scheme = scheme.to_ascii_lowercase();
        if PASSTHROUGH.contains(&scheme.as_str()) {
            if let Ok(u) = url::Url::parse(text) {
                if scheme == "http" || scheme == "https" {
                    return u.host_str().is_some().then(|| u.to_string());
                }
                return Some(u.to_string());
            }
        }
        if scheme == "javascript" || scheme == "data" || scheme == "vbscript" {
            return None;
        }
    }
    // host[:port][/path...]
    let host_end = text.find(['/', '?', '#']).unwrap_or(text.len());
    let authority = &text[..host_end];
    if authority.contains('@') {
        return None;
    }
    let (host, port) = split_port(authority)?;
    if host.is_empty() {
        return None;
    }
    let lower = host.to_ascii_lowercase();
    let local = lower == "localhost"
        || lower.ends_with(".local")
        || lower.ends_with(".localhost")
        || lower.parse::<std::net::Ipv4Addr>().is_ok()
        || (lower.starts_with('[') && lower.ends_with(']'));
    let scheme = if local {
        "http"
    } else {
        if !is_domain(&lower) {
            return None;
        }
        "https"
    };
    if !local && port.is_none() && lower.chars().all(|c| c.is_ascii_digit() || c == '.') {
        return None;
    }
    url::Url::parse(&format!("{scheme}://{text}"))
        .ok()
        .filter(|u| u.host_str().is_some())
        .map(|u| u.to_string())
}

fn split_port(authority: &str) -> Option<(&str, Option<u16>)> {
    if authority.starts_with('[') {
        let close = authority.find(']')?;
        let rest = &authority[close + 1..];
        let port = match rest.strip_prefix(':') {
            Some(p) => Some(p.parse().ok()?),
            None if rest.is_empty() => None,
            None => return None,
        };
        return Some((&authority[..=close], port));
    }
    match authority.rsplit_once(':') {
        Some((h, p)) => Some((h, Some(p.parse().ok()?))),
        None => Some((authority, None)),
    }
}

/// A dotted name whose labels are valid and whose suffix is on the public
/// suffix list (so `foo.bar` with an unknown TLD is a search).
fn is_domain(host: &str) -> bool {
    let host = host.trim_end_matches('.');
    if !host.contains('.') || host.starts_with('.') {
        return false;
    }
    let labels_ok = host.split('.').all(|l| {
        !l.is_empty()
            && l.len() <= 63
            && !l.starts_with('-')
            && !l.ends_with('-')
            && l.chars().all(|c| c.is_alphanumeric() || c == '-')
    });
    if !labels_ok {
        return false;
    }
    psl::suffix(host.as_bytes()).is_some_and(|s| s.is_known())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::search::builtin_engines;

    fn go(text: &str) -> Option<Navigation> {
        let engines = builtin_engines();
        let default = engines[0].clone();
        classify(text, &default, &|k| {
            engines.iter().find(|e| e.keyword == k).cloned()
        })
    }

    fn url(text: &str) -> String {
        match go(text) {
            Some(Navigation::Url { url }) => url,
            other => panic!("{text}: {other:?}"),
        }
    }

    fn query(text: &str) -> (String, String) {
        match go(text) {
            Some(Navigation::Search { engine, query, .. }) => (engine, query),
            other => panic!("{text}: {other:?}"),
        }
    }

    #[test]
    fn addresses() {
        assert_eq!(url("example.com"), "https://example.com/");
        assert_eq!(url("bbc.co.uk/news?x=1"), "https://bbc.co.uk/news?x=1");
        assert_eq!(url("HTTP://Example.com/A"), "http://example.com/A");
        assert_eq!(url("localhost:8080/app"), "http://localhost:8080/app");
        assert_eq!(url("192.168.1.1"), "http://192.168.1.1/");
        assert_eq!(url("printer.local"), "http://printer.local/");
        assert_eq!(url("[::1]:3000"), "http://[::1]:3000/");
        assert_eq!(url("about:blank"), "about:blank");
        assert_eq!(url("sub.example.org:8443"), "https://sub.example.org:8443/");
    }

    #[test]
    fn searches() {
        assert_eq!(
            query("rust lang"),
            ("duckduckgo".into(), "rust lang".into())
        );
        assert_eq!(query("hello"), ("duckduckgo".into(), "hello".into()));
        assert_eq!(
            query("foo.notatld"),
            ("duckduckgo".into(), "foo.notatld".into())
        );
        assert_eq!(
            query("w sailfish os"),
            ("wikipedia".into(), "sailfish os".into())
        );
        assert_eq!(
            query("?example.com"),
            ("duckduckgo".into(), "example.com".into())
        );
        assert_eq!(query("javascript:alert(1)").0, "duckduckgo");
        assert_eq!(query("data:text/html,hi").0, "duckduckgo");
        assert_eq!(
            query("user@example.com"),
            ("duckduckgo".into(), "user@example.com".into())
        );
        assert_eq!(query("3.14"), ("duckduckgo".into(), "3.14".into()));
        // A keyword alone is a plain search for that word.
        assert_eq!(query("w"), ("duckduckgo".into(), "w".into()));
        assert!(go("   ").is_none());
        assert!(go("?").is_none());
    }
}
