// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! "Clear browsing data" by time range.
//!
//! The profile database part is done here; what lives in the web engine
//! (cookies, site storage, cache) is returned as [`EngineClear`] for the
//! web view to do (`WebKitWebsiteDataManager` clears by time span).
//!
//! Pacific has no telemetry: nothing in the core or the app reports usage,
//! crashes or errors anywhere. The only network requests it makes on its
//! own are filter-list updates (to the lists' publishers) and, while
//! typing and only when enabled, search suggestions (to the default
//! search engine).

use serde::{Deserialize, Serialize};

use crate::db::Profile;
use crate::session::SessionStore;
use crate::Result;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Range {
    LastHour,
    Today,
    LastWeek,
    LastFourWeeks,
    All,
}

impl Range {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "last_hour" => Self::LastHour,
            "today" => Self::Today,
            "last_week" => Self::LastWeek,
            "last_four_weeks" => Self::LastFourWeeks,
            "all" => Self::All,
            _ => return None,
        })
    }

    /// The start of the range for `now_ms`; `utc_offset_s` puts "today" at
    /// local midnight.
    pub fn since(self, now_ms: i64, utc_offset_s: i64) -> i64 {
        const H: i64 = 3600 * 1000;
        match self {
            Self::LastHour => now_ms - H,
            Self::Today => {
                let local = now_ms + utc_offset_s * 1000;
                local - local.rem_euclid(24 * H) - utc_offset_s * 1000
            }
            Self::LastWeek => now_ms - 7 * 24 * H,
            Self::LastFourWeeks => now_ms - 28 * 24 * H,
            Self::All => 0,
        }
    }
}

/// What to clear.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(default)]
#[allow(clippy::struct_excessive_bools, reason = "independent check boxes")]
pub struct What {
    pub history: bool,
    pub cookies: bool,
    pub cache: bool,
    pub downloads: bool,
    pub site_settings: bool,
    /// Recently closed tabs and the saved session's back/forward lists.
    pub session: bool,
}

/// The engine's part, for the web view.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct EngineClear {
    pub cookies_and_site_data: bool,
    pub cache: bool,
    pub since_ms: i64,
}

/// Clears `what` in `range` from the profile (and the session files when
/// `session` is set and the range is everything).
pub fn clear(
    profile: &Profile,
    store: Option<&SessionStore>,
    range: Range,
    what: What,
    now_ms: i64,
    utc_offset_s: i64,
) -> Result<EngineClear> {
    let since = range.since(now_ms, utc_offset_s);
    if what.history {
        profile.delete_visits_between(since, i64::MAX)?;
        profile.clear_searches_since(since)?;
        if range == Range::All {
            profile.conn.execute_batch(
                "DELETE FROM input_history;
                 DELETE FROM places WHERE NOT EXISTS (SELECT 1 FROM bookmarks b WHERE b.url = places.url);
                 UPDATE places SET hidden = 0;",
            )?;
            profile.clear_protection_counts()?;
        }
    }
    if what.downloads {
        profile.conn.execute(
            "DELETE FROM downloads WHERE started >= ?1 AND state IN (2, 3, 4)",
            [since],
        )?;
    }
    if what.site_settings {
        profile.clear_site_settings_since(since)?;
        if range == Range::All {
            profile.conn.execute("DELETE FROM https_exceptions", [])?;
        } else {
            profile
                .conn
                .execute("DELETE FROM https_exceptions WHERE added >= ?1", [since])?;
        }
    }
    if what.session && range == Range::All {
        if let Some(s) = store {
            s.clear()?;
        }
    }
    profile.checkpoint()?;
    Ok(EngineClear {
        cookies_and_site_data: what.cookies,
        cache: what.cache,
        since_ms: since,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bookmarks::ROOT;
    use crate::frecency::Transition;

    const H: i64 = 3600 * 1000;

    #[test]
    fn ranges() {
        let now = 1000 * 24 * H + 15 * H; // 15:00 UTC
        assert_eq!(Range::LastHour.since(now, 0), now - H);
        assert_eq!(Range::Today.since(now, 0), 1000 * 24 * H);
        // At UTC+3 it is 18:00 local; local midnight is 21:00 UTC before.
        assert_eq!(Range::Today.since(now, 3 * 3600), 1000 * 24 * H - 3 * H);
        assert_eq!(Range::All.since(now, 0), 0);
        assert_eq!(Range::parse("last_week"), Some(Range::LastWeek));
        assert_eq!(Range::parse("x"), None);
    }

    #[test]
    fn clears_the_last_hour_only() {
        let p = Profile::in_memory().unwrap();
        let now = 500 * 24 * H;
        p.record_visit("https://old.example/", None, Transition::Link, now - 5 * H)
            .unwrap();
        p.record_visit("https://new.example/", None, Transition::Link, now - 10_000)
            .unwrap();
        p.set_site_setting("new.example", "zoom", "1.5").unwrap();
        let e = clear(
            &p,
            None,
            Range::LastHour,
            What {
                history: true,
                cookies: true,
                ..What::default()
            },
            now,
            0,
        )
        .unwrap();
        assert!(e.cookies_and_site_data && !e.cache);
        assert_eq!(e.since_ms, now - H);
        assert!(p.place("https://old.example/").unwrap().is_some());
        assert!(p.place("https://new.example/").unwrap().is_none());
        // Site settings were not chosen.
        assert_eq!(p.site_settings("new.example").unwrap().zoom, Some(1.5));
    }

    #[test]
    fn clears_everything_but_bookmarks() {
        let d = tempfile::tempdir().unwrap();
        let store = SessionStore::new(d.path());
        store.save(&crate::session::Session::default()).unwrap();
        let p = Profile::in_memory().unwrap();
        p.add_bookmark("https://kept.example/", "Kept", ROOT)
            .unwrap();
        p.record_visit("https://kept.example/", None, Transition::Typed, 1000)
            .unwrap();
        p.record_visit("https://gone.example/", None, Transition::Typed, 1000)
            .unwrap();
        p.record_selection("ke", "https://kept.example/").unwrap();
        p.add_https_exception("http.example", 5).unwrap();
        let all = What {
            history: true,
            cookies: true,
            cache: true,
            downloads: true,
            site_settings: true,
            session: true,
        };
        clear(&p, Some(&store), Range::All, all, 10_000, 0).unwrap();
        assert!(p.place("https://gone.example/").unwrap().is_none());
        let kept = p.place("https://kept.example/").unwrap().unwrap();
        assert_eq!(kept.visit_count, 0);
        assert!(p.is_bookmarked("https://kept.example/").unwrap());
        assert!(p.https_exceptions().unwrap().is_empty());
        assert!(!d.path().join("session.lz4").exists());
    }
}
