// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Small helpers shared by the modules: time, hosts, atomic files.

use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::{Error, Result};

/// Milliseconds since the Unix epoch.
pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
}

/// The host of `url`, lower case, without a leading `www.`; empty when the
/// URL has none (`about:blank`, `data:`).
pub fn display_host(url: &str) -> String {
    let host = url::Url::parse(url)
        .ok()
        .and_then(|u| u.host_str().map(str::to_ascii_lowercase))
        .unwrap_or_default();
    host.strip_prefix("www.").map(str::to_owned).unwrap_or(host)
}

/// The host of `url`, lower case (with `www.` kept), or empty.
pub fn host_of(url: &str) -> String {
    url::Url::parse(url)
        .ok()
        .and_then(|u| u.host_str().map(str::to_ascii_lowercase))
        .unwrap_or_default()
}

/// The registrable domain (eTLD+1) of a host, from the public suffix list;
/// the host itself when it has none (an IP address, `localhost`).
pub fn site_of(host: &str) -> String {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if host.starts_with('[') || host.parse::<std::net::IpAddr>().is_ok() {
        return host;
    }
    psl::domain_str(&host).map_or(host.clone(), str::to_owned)
}

/// A short name for a site: its registrable domain without the public
/// suffix (`en.wikipedia.org` is `wikipedia`, `www.bbc.co.uk` is `bbc`);
/// the host itself for an IP address or a bare name like `localhost`.
pub fn site_name(host: &str) -> String {
    let site = site_of(host);
    if site.starts_with('[') || site.parse::<std::net::IpAddr>().is_ok() {
        return site;
    }
    match psl::suffix_str(&site) {
        Some(suffix) if site.len() > suffix.len() + 1 => {
            site[..site.len() - suffix.len() - 1].to_owned()
        }
        _ => site,
    }
}

/// Writes `bytes` to `path` atomically: a temporary file in the same
/// directory, fsync, rename. Mode 0600 on Unix.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(dir).map_err(|e| Error::io(dir, e))?;
    let tmp = path.with_extension(format!(
        "{}.tmp",
        path.extension().and_then(|e| e.to_str()).unwrap_or("")
    ));
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp).map_err(|e| Error::io(&tmp, e))?;
        f.write_all(bytes).map_err(|e| Error::io(&tmp, e))?;
        f.sync_all().map_err(|e| Error::io(&tmp, e))?;
    }
    std::fs::rename(&tmp, path).map_err(|e| Error::io(path, e))?;
    Ok(())
}

/// `text` cut to at most `max` characters (not bytes), on a char boundary,
/// with an ellipsis when cut.
pub fn truncate_chars(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_owned();
    }
    let mut out: String = text.chars().take(max.saturating_sub(1)).collect();
    out.push('\u{2026}');
    out
}

/// Escapes text for HTML element content and attribute values.
pub fn html_escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

/// `text` as a JavaScript string literal (JSON is a subset of JS, with the
/// two line separators JSON allows but older JS engines do not).
pub fn js_string(text: &str) -> String {
    serde_json::to_string(text)
        .unwrap_or_else(|_| "\"\"".into())
        .replace('\u{2028}', "\\u2028")
        .replace('\u{2029}', "\\u2029")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hosts() {
        assert_eq!(display_host("https://www.Example.com/a"), "example.com");
        assert_eq!(host_of("https://www.example.com/a"), "www.example.com");
        assert_eq!(display_host("about:blank"), "");
        assert_eq!(site_of("news.bbc.co.uk"), "bbc.co.uk");
        assert_eq!(site_of("localhost"), "localhost");
        assert_eq!(site_name("en.wikipedia.org"), "wikipedia");
        assert_eq!(site_name("www.bbc.co.uk"), "bbc");
        assert_eq!(site_name("duckduckgo.com"), "duckduckgo");
        assert_eq!(site_name("localhost"), "localhost");
        assert_eq!(site_name("127.0.0.1"), "127.0.0.1");
        assert_eq!(site_of("192.168.1.20"), "192.168.1.20");
    }

    #[test]
    fn truncation_and_escaping() {
        assert_eq!(truncate_chars("héllo", 10), "héllo");
        assert_eq!(truncate_chars("héllo world", 4), "hél\u{2026}");
        assert_eq!(
            html_escape("<a href=\"x\">&'"),
            "&lt;a href=&quot;x&quot;&gt;&amp;&#39;"
        );
        assert_eq!(js_string("a\"b\u{2028}"), "\"a\\\"b\\u2028\"");
    }

    #[test]
    fn atomic_write() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("sub/file.json");
        write_atomic(&p, b"one").unwrap();
        write_atomic(&p, b"two").unwrap();
        assert_eq!(std::fs::read(&p).unwrap(), b"two");
        assert!(!d.path().join("sub/file.json.tmp").exists());
    }
}
