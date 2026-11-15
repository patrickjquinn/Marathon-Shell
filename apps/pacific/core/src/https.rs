// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! HTTPS-first: every `http://` navigation is tried over `https://`
//! first. If the secure load fails (certificate or connection error, or no
//! answer within [`TIMEOUT_MS`]), the person sees an interstitial and may
//! continue over HTTP; the host is then remembered as an exception (for
//! the profile, or only for the private session). If the HTTPS site
//! redirects straight back to HTTP, the HTTP page is loaded without asking
//! and the host remembered, as Brave and Chrome do.
//!
//! No upgrade list is used: DuckDuckGo's Smarter Encryption data is
//! CC BY-NC-SA, so this is the upgrade-then-fall-back approach instead.
//! Never upgraded: `localhost`, `.local`, `.onion`, IP addresses and
//! single-label hosts (intranets rarely have certificates).

use std::collections::{HashMap, HashSet};

use rusqlite::params;
use serde::Serialize;

use crate::db::Profile;
use crate::Result;

/// How long a secure load may take before falling back.
pub const TIMEOUT_MS: i64 = 3_000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum Step {
    /// Load this URL instead (the upgrade).
    Load { url: String },
    /// Let the navigation go ahead unchanged.
    Proceed,
    /// Show the interstitial for `http_url`.
    Interstitial { http_url: String, host: String },
}

#[derive(Debug, Clone)]
struct Pending {
    https_url: String,
    http_url: String,
    host: String,
    started: i64,
}

/// Per-window HTTPS-first state.
#[derive(Debug, Default)]
pub struct HttpsFirst {
    pub enabled: bool,
    pending: HashMap<i64, Pending>,
    /// Exceptions for private tabs (never written).
    session_exceptions: HashSet<String>,
}

/// Whether `host` may be upgraded at all.
#[allow(
    clippy::case_sensitive_file_extension_comparisons,
    reason = "host suffixes, lower-cased first"
)]
pub fn upgradable_host(host: &str) -> bool {
    let h = host.trim_end_matches('.').to_ascii_lowercase();
    !(h.is_empty()
        || !h.contains('.')
        || h == "localhost"
        || h.ends_with(".localhost")
        || h.ends_with(".local")
        || h.ends_with(".onion")
        || h.parse::<std::net::IpAddr>().is_ok()
        || h.starts_with('['))
}

impl HttpsFirst {
    pub fn new(enabled: bool) -> Self {
        Self {
            enabled,
            ..Self::default()
        }
    }

    fn is_exception(&self, profile: Option<&Profile>, host: &str) -> Result<bool> {
        if self.session_exceptions.contains(host) {
            return Ok(true);
        }
        match profile {
            Some(p) => p.is_https_exception(host),
            None => Ok(false),
        }
    }

    /// A navigation in `tab` to `url` is about to start. `profile` is
    /// `None` for private tabs.
    pub fn navigate(
        &mut self,
        tab: i64,
        url: &str,
        profile: Option<&Profile>,
        now: i64,
    ) -> Result<Step> {
        let Ok(parsed) = url::Url::parse(url) else {
            return Ok(Step::Proceed);
        };
        let host = parsed.host_str().unwrap_or("").to_ascii_lowercase();
        if parsed.scheme() == "http" {
            // The HTTPS attempt redirected back to HTTP on the same host.
            if self.pending.get(&tab).is_some_and(|p| p.host == host) {
                self.pending.remove(&tab);
                self.add_exception(profile, &host, now)?;
                return Ok(Step::Proceed);
            }
            if !self.enabled || !upgradable_host(&host) || self.is_exception(profile, &host)? {
                return Ok(Step::Proceed);
            }
            let mut up = parsed.clone();
            if up.set_scheme("https").is_err() {
                return Ok(Step::Proceed);
            }
            // An explicit :80 does not carry over to HTTPS.
            if up.port() == Some(80) {
                let _ = up.set_port(None);
            }
            let https_url = up.to_string();
            self.pending.insert(
                tab,
                Pending {
                    https_url: https_url.clone(),
                    http_url: url.to_owned(),
                    host,
                    started: now,
                },
            );
            return Ok(Step::Load { url: https_url });
        }
        // Any other navigation ends a pending upgrade unless it is the
        // upgrade itself (or a redirect within the same host).
        if let Some(p) = self.pending.get(&tab) {
            if p.https_url != url && p.host != host {
                self.pending.remove(&tab);
            }
        }
        Ok(Step::Proceed)
    }

    /// The page in `tab` finished loading `url`; returns true when this
    /// completed an upgrade (count it in the stats).
    pub fn load_finished(&mut self, tab: i64, url: &str) -> bool {
        let host = url::Url::parse(url)
            .ok()
            .and_then(|u| u.host_str().map(str::to_ascii_lowercase));
        match self.pending.get(&tab) {
            Some(p) if url.starts_with("https:") && host.as_deref() == Some(p.host.as_str()) => {
                self.pending.remove(&tab);
                true
            }
            _ => false,
        }
    }

    /// The load in `tab` failed. If it was an upgrade attempt, the
    /// interstitial is due.
    pub fn load_failed(&mut self, tab: i64) -> Step {
        match self.pending.remove(&tab) {
            Some(p) => Step::Interstitial {
                http_url: p.http_url,
                host: p.host,
            },
            None => Step::Proceed,
        }
    }

    /// Called by the UI's timer: an upgrade attempt older than
    /// [`TIMEOUT_MS`] is given up (interstitial).
    pub fn check_timeout(&mut self, tab: i64, now: i64) -> Step {
        match self.pending.get(&tab) {
            Some(p) if now - p.started >= TIMEOUT_MS => self.load_failed(tab),
            _ => Step::Proceed,
        }
    }

    pub fn is_pending(&self, tab: i64) -> bool {
        self.pending.contains_key(&tab)
    }

    /// The person chose "continue over HTTP" for `host`.
    pub fn add_exception(&mut self, profile: Option<&Profile>, host: &str, now: i64) -> Result<()> {
        if let Some(p) = profile {
            p.add_https_exception(host, now)
        } else {
            self.session_exceptions.insert(host.to_ascii_lowercase());
            Ok(())
        }
    }

    pub fn tab_closed(&mut self, tab: i64) {
        self.pending.remove(&tab);
    }
}

impl Profile {
    pub fn is_https_exception(&self, host: &str) -> Result<bool> {
        use rusqlite::OptionalExtension;
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM https_exceptions WHERE host = ?1",
                [host.to_ascii_lowercase()],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    pub fn add_https_exception(&self, host: &str, now: i64) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO https_exceptions(host, added) VALUES (?1, ?2)",
            params![host.to_ascii_lowercase(), now],
        )?;
        Ok(())
    }

    pub fn https_exceptions(&self) -> Result<Vec<String>> {
        let mut stmt = self
            .conn
            .prepare_cached("SELECT host FROM https_exceptions ORDER BY host")?;
        let rows = stmt
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    pub fn remove_https_exception(&self, host: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM https_exceptions WHERE host = ?1",
            [host.to_ascii_lowercase()],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upgrades_and_completes() {
        let p = Profile::in_memory().unwrap();
        let mut h = HttpsFirst::new(true);
        let s = h
            .navigate(1, "http://example.com:80/a?b=1", Some(&p), 0)
            .unwrap();
        assert_eq!(
            s,
            Step::Load {
                url: "https://example.com/a?b=1".into()
            }
        );
        assert!(h.is_pending(1));
        assert_eq!(
            h.navigate(1, "https://example.com/a?b=1", Some(&p), 1)
                .unwrap(),
            Step::Proceed
        );
        assert!(h.is_pending(1));
        assert!(h.load_finished(1, "https://example.com/a?b=1"));
        assert!(!h.is_pending(1));
    }

    #[test]
    fn failure_shows_interstitial_and_remembers() {
        let p = Profile::in_memory().unwrap();
        let mut h = HttpsFirst::new(true);
        h.navigate(1, "http://old.example/", Some(&p), 0).unwrap();
        assert_eq!(
            h.load_failed(1),
            Step::Interstitial {
                http_url: "http://old.example/".into(),
                host: "old.example".into()
            }
        );
        h.add_exception(Some(&p), "old.example", 5).unwrap();
        assert_eq!(
            h.navigate(1, "http://old.example/", Some(&p), 6).unwrap(),
            Step::Proceed
        );
        assert_eq!(p.https_exceptions().unwrap(), ["old.example"]);
        p.remove_https_exception("old.example").unwrap();
        assert!(matches!(
            h.navigate(1, "http://old.example/", Some(&p), 7).unwrap(),
            Step::Load { .. }
        ));
        assert_eq!(h.load_failed(2), Step::Proceed);
    }

    #[test]
    fn timeout() {
        let mut h = HttpsFirst::new(true);
        h.navigate(3, "http://slow.example/", None, 1000).unwrap();
        assert_eq!(h.check_timeout(3, 2000), Step::Proceed);
        assert!(matches!(
            h.check_timeout(3, 1000 + TIMEOUT_MS),
            Step::Interstitial { .. }
        ));
    }

    #[test]
    fn redirect_back_to_http_is_accepted_quietly() {
        let mut h = HttpsFirst::new(true);
        h.navigate(1, "http://downgrade.example/", None, 0).unwrap();
        // The HTTPS site answered with a redirect to HTTP.
        assert_eq!(
            h.navigate(1, "http://downgrade.example/", None, 1).unwrap(),
            Step::Proceed
        );
        // Private session exception: remembered, not written.
        assert_eq!(
            h.navigate(1, "http://downgrade.example/x", None, 2)
                .unwrap(),
            Step::Proceed
        );
    }

    #[test]
    fn never_upgraded() {
        let mut h = HttpsFirst::new(true);
        for u in [
            "http://localhost:8080/",
            "http://192.168.0.1/",
            "http://printer.local/",
            "http://intranet/",
            "http://x.onion/",
            "https://a.example/",
            "about:blank",
        ] {
            assert_eq!(h.navigate(1, u, None, 0).unwrap(), Step::Proceed, "{u}");
        }
        let mut off = HttpsFirst::new(false);
        assert_eq!(
            off.navigate(1, "http://example.com/", None, 0).unwrap(),
            Step::Proceed
        );
    }

    #[test]
    fn leaving_cancels_pending() {
        let mut h = HttpsFirst::new(true);
        h.navigate(1, "http://a.example/", None, 0).unwrap();
        h.navigate(1, "https://elsewhere.example/", None, 1)
            .unwrap();
        assert!(!h.is_pending(1));
        h.navigate(2, "http://b.example/", None, 0).unwrap();
        h.tab_closed(2);
        assert!(!h.is_pending(2));
    }
}
