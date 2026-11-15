// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! What protection did: per page (the shield in the address bar) and per
//! day (the privacy dashboard in Settings). Counts only; no URLs are kept
//! past the page.
//!
//! A page can have hundreds of blocked requests. Each one updates the
//! page's counts at once, in memory; [`StatsBook`] also remembers which
//! tabs changed and the counts not yet written, and the app tells the UI
//! and writes the profile in batches: [`StatsBook::take_changed`] at most
//! every [`EMIT_INTERVAL_MS`], [`StatsBook::take_writes`] at most every
//! [`WRITE_INTERVAL_MS`] (and always on a page change, a tab closing and
//! at exit), until [`StatsBook::is_settled`].

use std::collections::{BTreeMap, BTreeSet, HashMap};

use rusqlite::params;
use serde::Serialize;

use crate::db::Profile;
use crate::util::{host_of, site_of};
use crate::Result;

/// Kinds counted per day.
pub const KIND_ADS: &str = "blocked";
pub const KIND_COOKIE_BANNERS: &str = "cookie_banners";
pub const KIND_HTTPS_UPGRADES: &str = "https_upgrades";

/// How often the UI hears that a page's counts changed, at most.
pub const EMIT_INTERVAL_MS: u64 = 250;
/// How often the day's counts are written, at most.
pub const WRITE_INTERVAL_MS: i64 = 1000;

/// One page's protection summary.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct PageStats {
    pub page_url: String,
    pub blocked: u32,
    /// Blocked requests by the site they went to, most first (at most 20).
    pub by_site: Vec<(String, u32)>,
    pub cookie_banner_handled: bool,
    pub https_upgraded: bool,
}

/// One page's running counts.
#[derive(Debug, Default)]
struct Counts {
    url: String,
    blocked: u32,
    sites: BTreeMap<String, u32>,
    cookie: bool,
    https: bool,
}

/// Per-tab running counts.
#[derive(Debug, Default)]
pub struct StatsBook {
    pages: HashMap<i64, Counts>,
    /// Tabs whose counts changed since [`Self::take_changed`].
    changed: BTreeSet<i64>,
    /// Blocked requests not yet written to the profile.
    unsaved_blocked: i64,
    last_write_ms: i64,
}

impl StatsBook {
    /// A new page started loading in `tab`: its counts start at zero.
    pub fn navigated(&mut self, tab: i64, page_url: &str) {
        self.pages.insert(
            tab,
            Counts {
                url: page_url.to_owned(),
                ..Counts::default()
            },
        );
    }

    /// A request from `tab`'s page was blocked: counted now, told and
    /// written later.
    pub fn blocked(&mut self, tab: i64, request_url: &str) {
        let entry = self.pages.entry(tab).or_default();
        entry.blocked = entry.blocked.saturating_add(1);
        let site = site_of(&host_of(request_url));
        if !site.is_empty() && entry.sites.len() < 200 {
            *entry.sites.entry(site).or_default() += 1;
        }
        self.changed.insert(tab);
        self.unsaved_blocked = self.unsaved_blocked.saturating_add(1);
    }

    /// The tabs whose counts changed since the last call.
    pub fn take_changed(&mut self) -> Vec<i64> {
        std::mem::take(&mut self.changed).into_iter().collect()
    }

    /// The counts to add to the profile now: everything not yet written
    /// when `force` or [`WRITE_INTERVAL_MS`] has passed since the last
    /// write, else nothing (they wait for a later call).
    pub fn take_writes(&mut self, now_ms: i64, force: bool) -> Vec<(&'static str, i64)> {
        if self.unsaved_blocked == 0 || !(force || now_ms - self.last_write_ms >= WRITE_INTERVAL_MS)
        {
            return Vec::new();
        }
        self.last_write_ms = now_ms;
        vec![(KIND_ADS, std::mem::take(&mut self.unsaved_blocked))]
    }

    /// Nothing left to tell or write.
    pub fn is_settled(&self) -> bool {
        self.changed.is_empty() && self.unsaved_blocked == 0
    }

    /// A cookie banner was answered on `tab`'s page; true the first time
    /// for the page (autoconsent in several frames reports each).
    pub fn cookie_banner(&mut self, tab: i64) -> bool {
        !std::mem::replace(&mut self.pages.entry(tab).or_default().cookie, true)
    }

    pub fn https_upgraded(&mut self, tab: i64) {
        self.pages.entry(tab).or_default().https = true;
    }

    pub fn closed(&mut self, tab: i64) {
        self.pages.remove(&tab);
        self.changed.remove(&tab);
    }

    pub fn page(&self, tab: i64) -> PageStats {
        let Some(c) = self.pages.get(&tab) else {
            return PageStats::default();
        };
        let mut by_site: Vec<(String, u32)> =
            c.sites.iter().map(|(k, v)| (k.clone(), *v)).collect();
        by_site.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        by_site.truncate(20);
        PageStats {
            page_url: c.url.clone(),
            blocked: c.blocked,
            by_site,
            cookie_banner_handled: c.cookie,
            https_upgraded: c.https,
        }
    }
}

/// Totals for the privacy dashboard.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Totals {
    pub blocked: i64,
    pub cookie_banners: i64,
    pub https_upgrades: i64,
    /// Rough data saved: 50 KB per blocked request (a conservative
    /// average of blocked scripts and images).
    pub bytes_saved_estimate: i64,
}

/// Days since the epoch (UTC) for a time in ms.
pub fn day_of(ms: i64) -> i64 {
    ms.div_euclid(24 * 3600 * 1000)
}

impl Profile {
    /// Adds `n` to today's count of `kind` (never for private tabs).
    pub fn add_protection_count(&self, kind: &str, n: i64, now_ms: i64) -> Result<()> {
        if n <= 0 || self.is_ephemeral() {
            return Ok(());
        }
        self.conn.execute(
            "INSERT INTO blocked_daily(day, kind, count) VALUES (?1, ?2, ?3)
             ON CONFLICT(day, kind) DO UPDATE SET count = count + excluded.count",
            params![day_of(now_ms), kind, n],
        )?;
        Ok(())
    }

    /// Totals since `since_ms` (0: all time).
    pub fn protection_totals(&self, since_ms: i64) -> Result<Totals> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT kind, sum(count) FROM blocked_daily WHERE day >= ?1 GROUP BY kind",
        )?;
        let mut t = Totals::default();
        for row in stmt.query_map([day_of(since_ms)], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        })? {
            let (k, n) = row?;
            match k.as_str() {
                KIND_ADS => t.blocked = n,
                KIND_COOKIE_BANNERS => t.cookie_banners = n,
                KIND_HTTPS_UPGRADES => t.https_upgrades = n,
                _ => {}
            }
        }
        t.bytes_saved_estimate = t.blocked.saturating_mul(50 * 1024);
        Ok(t)
    }

    pub fn clear_protection_counts(&self) -> Result<()> {
        self.conn.execute("DELETE FROM blocked_daily", [])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn per_page_counts() {
        let mut b = StatsBook::default();
        b.navigated(1, "https://news.example/");
        b.blocked(1, "https://ads.tracker.com/a.js");
        b.blocked(1, "https://cdn.tracker.com/b.js");
        b.blocked(1, "https://other.net/c.gif");
        assert!(b.cookie_banner(1));
        assert!(!b.cookie_banner(1));
        let p = b.page(1);
        assert_eq!(p.blocked, 3);
        assert_eq!(
            p.by_site,
            [("tracker.com".to_string(), 2), ("other.net".to_string(), 1)]
        );
        assert!(p.cookie_banner_handled);
        b.navigated(1, "https://news.example/2");
        assert_eq!(b.page(1).blocked, 0);
        b.closed(1);
        assert_eq!(b.page(1), PageStats::default());
    }

    #[test]
    fn blocked_requests_are_told_and_written_in_batches() {
        let mut b = StatsBook::default();
        b.navigated(1, "https://news.example/");
        b.navigated(2, "https://other.example/");
        for i in 0..300 {
            b.blocked(1, &format!("https://ads.example/{i}.js"));
        }
        b.blocked(2, "https://ads.example/x.js");
        // Counted at once.
        assert_eq!(b.page(1).blocked, 300);
        assert!(!b.is_settled());
        // One notice per changed tab, however many requests.
        assert_eq!(b.take_changed(), [1, 2]);
        assert!(b.take_changed().is_empty());
        // One write for all of them; the next waits for the interval.
        assert_eq!(b.take_writes(5_000, false), [(KIND_ADS, 301)]);
        assert!(b.is_settled());
        b.blocked(1, "https://ads.example/late.js");
        assert!(b
            .take_writes(5_000 + WRITE_INTERVAL_MS - 1, false)
            .is_empty());
        assert!(!b.is_settled());
        assert_eq!(
            b.take_writes(5_000 + WRITE_INTERVAL_MS, false),
            [(KIND_ADS, 1)]
        );
        // A forced write (page change, tab closed, exit) does not wait,
        // and nothing is lost or written twice.
        b.blocked(1, "https://ads.example/a.js");
        b.blocked(1, "https://ads.example/b.js");
        assert_eq!(
            b.take_writes(5_001 + WRITE_INTERVAL_MS, true),
            [(KIND_ADS, 2)]
        );
        assert!(b.take_writes(1 << 40, true).is_empty());
        // A closed tab is not told about.
        b.closed(1);
        assert!(b.take_changed().is_empty());
        assert!(b.is_settled());
    }

    #[test]
    fn daily_totals() {
        let p = Profile::in_memory().unwrap();
        // In-memory (private) profiles count nothing.
        p.add_protection_count(KIND_ADS, 5, 0).unwrap();
        assert_eq!(p.protection_totals(0).unwrap(), Totals::default());
        let d = tempfile::tempdir().unwrap();
        let p = Profile::open(d.path()).unwrap();
        let day = 24 * 3600 * 1000;
        p.add_protection_count(KIND_ADS, 5, day).unwrap();
        p.add_protection_count(KIND_ADS, 2, 10 * day).unwrap();
        p.add_protection_count(KIND_COOKIE_BANNERS, 1, 10 * day)
            .unwrap();
        let all = p.protection_totals(0).unwrap();
        assert_eq!((all.blocked, all.cookie_banners), (7, 1));
        assert_eq!(all.bytes_saved_estimate, 7 * 50 * 1024);
        assert_eq!(p.protection_totals(5 * day).unwrap().blocked, 2);
        p.clear_protection_counts().unwrap();
        assert_eq!(p.protection_totals(0).unwrap().blocked, 0);
    }
}
