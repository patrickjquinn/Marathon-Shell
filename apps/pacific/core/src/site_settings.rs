// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Per-site settings: zoom, desktop site, JavaScript, content blocking,
//! autoplay and the answers to permission prompts. A site is its host
//! without `www.`. Anything not set follows the global settings.

use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::db::Profile;
use crate::util::{display_host, now_ms};
use crate::{Error, Result};

/// Permission prompt answers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Answer {
    Ask,
    Allow,
    Deny,
}

/// Permissions a site can ask for.
pub const PERMISSIONS: &[&str] = &[
    "location",
    "camera",
    "microphone",
    "notifications",
    "persistent-storage",
    "clipboard",
];

/// The settings of one site; `None` follows the global setting.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SiteSettings {
    pub site: String,
    pub zoom: Option<f64>,
    pub desktop: Option<bool>,
    pub javascript: Option<bool>,
    pub blocking: Option<bool>,
    pub autoplay: Option<bool>,
    /// (permission, answer) for answered prompts.
    pub permissions: Vec<(String, Answer)>,
}

impl SiteSettings {
    pub fn permission(&self, name: &str) -> Answer {
        self.permissions
            .iter()
            .find(|(n, _)| n == name)
            .map_or(Answer::Ask, |(_, a)| *a)
    }

    /// Whether anything is set.
    pub fn is_empty(&self) -> bool {
        self.zoom.is_none()
            && self.desktop.is_none()
            && self.javascript.is_none()
            && self.blocking.is_none()
            && self.autoplay.is_none()
            && self.permissions.is_empty()
    }
}

/// The site key of a URL or host.
pub fn site_key(url_or_host: &str) -> String {
    let lower = url_or_host.trim().to_ascii_lowercase();
    let is_url = lower.contains("://")
        || ["about:", "data:", "file:", "javascript:", "blob:"]
            .iter()
            .any(|s| lower.starts_with(s));
    if is_url {
        display_host(url_or_host)
    } else {
        let h = url_or_host.trim().to_ascii_lowercase();
        h.strip_prefix("www.").map(str::to_owned).unwrap_or(h)
    }
}

const KEYS: &[&str] = &["zoom", "desktop", "javascript", "blocking", "autoplay"];

impl Profile {
    pub fn site_settings(&self, url_or_host: &str) -> Result<SiteSettings> {
        let site = site_key(url_or_host);
        let mut out = SiteSettings {
            site: site.clone(),
            ..SiteSettings::default()
        };
        let mut stmt = self
            .conn
            .prepare_cached("SELECT key, value FROM site_settings WHERE host = ?1 ORDER BY key")?;
        for row in stmt.query_map([&site], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })? {
            let (key, value) = row?;
            let flag = || value == "1";
            match key.as_str() {
                "zoom" => out.zoom = value.parse().ok(),
                "desktop" => out.desktop = Some(flag()),
                "javascript" => out.javascript = Some(flag()),
                "blocking" => out.blocking = Some(flag()),
                "autoplay" => out.autoplay = Some(flag()),
                p if p.starts_with("perm.") => {
                    let a = match value.as_str() {
                        "allow" => Answer::Allow,
                        "deny" => Answer::Deny,
                        _ => continue,
                    };
                    out.permissions.push((p["perm.".len()..].to_owned(), a));
                }
                _ => {}
            }
        }
        Ok(out)
    }

    /// Sets `key` (zoom, desktop, javascript, blocking, autoplay, or
    /// `perm.<permission>`) for a site; an empty `value` clears it.
    pub fn set_site_setting(&self, url_or_host: &str, key: &str, value: &str) -> Result<()> {
        let site = site_key(url_or_host);
        if site.is_empty() {
            return Err(Error::Invalid("this page has no site".into()));
        }
        let valid = KEYS.contains(&key)
            || key
                .strip_prefix("perm.")
                .is_some_and(|p| PERMISSIONS.contains(&p));
        if !valid {
            return Err(Error::Invalid(format!("unknown site setting {key}")));
        }
        if value.is_empty() || value == "ask" {
            self.conn.execute(
                "DELETE FROM site_settings WHERE host = ?1 AND key = ?2",
                params![site, key],
            )?;
            return Ok(());
        }
        let ok = match key {
            "zoom" => value.parse::<f64>().is_ok_and(|z| (0.3..=3.0).contains(&z)),
            k if k.starts_with("perm.") => value == "allow" || value == "deny",
            _ => value == "0" || value == "1",
        };
        if !ok {
            return Err(Error::Invalid(format!(
                "{key}: {value} is not a valid value"
            )));
        }
        self.conn.execute(
            "INSERT INTO site_settings(host, key, value, modified) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(host, key) DO UPDATE SET value = excluded.value, modified = excluded.modified",
            params![site, key, value, now_ms()],
        )?;
        Ok(())
    }

    pub fn clear_site_settings(&self, url_or_host: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM site_settings WHERE host = ?1",
            [site_key(url_or_host)],
        )?;
        Ok(())
    }

    /// Every site with something set, by name.
    pub fn sites_with_settings(&self) -> Result<Vec<SiteSettings>> {
        let hosts: Vec<String> = {
            let mut stmt = self
                .conn
                .prepare_cached("SELECT DISTINCT host FROM site_settings ORDER BY host")?;
            let rows = stmt
                .query_map([], |r| r.get(0))?
                .collect::<rusqlite::Result<_>>()?;
            rows
        };
        hosts.iter().map(|h| self.site_settings(h)).collect()
    }

    /// Sites with content blocking turned off.
    pub fn blocking_allowlist(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT host FROM site_settings WHERE key = 'blocking' AND value = '0' ORDER BY host",
        )?;
        let rows = stmt
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    /// Clears settings changed at or after `since_ms` (clear data by time).
    pub fn clear_site_settings_since(&self, since_ms: i64) -> Result<usize> {
        Ok(self
            .conn
            .execute("DELETE FROM site_settings WHERE modified >= ?1", [since_ms])?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_get_clear() {
        let p = Profile::in_memory().unwrap();
        p.set_site_setting("https://www.example.com/a", "zoom", "1.25")
            .unwrap();
        p.set_site_setting("example.com", "desktop", "1").unwrap();
        p.set_site_setting("example.com", "blocking", "0").unwrap();
        p.set_site_setting("example.com", "perm.location", "deny")
            .unwrap();
        let s = p.site_settings("https://example.com/b").unwrap();
        assert_eq!(s.site, "example.com");
        assert_eq!(s.zoom, Some(1.25));
        assert_eq!(s.desktop, Some(true));
        assert_eq!(s.blocking, Some(false));
        assert_eq!(s.javascript, None);
        assert_eq!(s.permission("location"), Answer::Deny);
        assert_eq!(s.permission("camera"), Answer::Ask);
        assert_eq!(p.blocking_allowlist().unwrap(), ["example.com"]);
        p.set_site_setting("example.com", "perm.location", "ask")
            .unwrap();
        assert_eq!(
            p.site_settings("example.com")
                .unwrap()
                .permission("location"),
            Answer::Ask
        );
        assert_eq!(p.sites_with_settings().unwrap().len(), 1);
        p.clear_site_settings("www.example.com").unwrap();
        assert!(p.site_settings("example.com").unwrap().is_empty());
    }

    #[test]
    fn validation() {
        let p = Profile::in_memory().unwrap();
        assert!(p.set_site_setting("e.com", "zoom", "9").is_err());
        assert!(p.set_site_setting("e.com", "zoom", "abc").is_err());
        assert!(p.set_site_setting("e.com", "desktop", "yes").is_err());
        assert!(p
            .set_site_setting("e.com", "perm.teleport", "allow")
            .is_err());
        assert!(p.set_site_setting("e.com", "nonsense", "1").is_err());
        assert!(p.set_site_setting("about:blank", "zoom", "1").is_err());
        p.set_site_setting("e.com", "javascript", "0").unwrap();
        assert_eq!(p.clear_site_settings_since(0).unwrap(), 1);
    }
}
