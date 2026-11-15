// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Address-bar suggestions.
//!
//! For typed text the list is, in order:
//!
//! 1. The *heuristic* first row: open the address, or search the default
//!    (or keyword) engine for the text. Enter always does what this row
//!    says.
//! 2. Pages from history and bookmarks, ranked by
//!    `relevance = log2(1 + frecency score) + topicality`, where the
//!    frecency score is the current exponential-decay score (frecency.rs)
//!    and topicality rewards where the words matched, in the spirit of
//!    Chromium's `HistoryQuick` provider:
//!    the host starts with the first word 10, the host contains a word 4
//!    (each), the path contains a word 2, the title has a word at a word
//!    start 3 (each), the page was typed before 2, it is bookmarked 3,
//!    and the adaptive *input history* adds `5 * min(use count, 4)` when
//!    the person chose this page after typing text that starts with what
//!    is typed now (Firefox's `moz_inputhistory`; [`Profile::record_selection`]).
//!    Pages must match every word (FTS5 prefix match on title and URL).
//! 3. Open tabs that match, as "switch to tab".
//! 4. The search engine's own suggestions (fetched by the app, off the GUI
//!    thread, only when allowed by [`may_fetch_remote`]).
//!
//! Inline completion ([`Suggestions::autofill`]) completes the host of the
//! most frecent page whose host starts with the typed text, as Firefox
//! does: `exa` becomes `example.com/` with the added part selected.

use std::collections::HashSet;

use rusqlite::params;
use serde::Serialize;

use crate::db::Profile;
use crate::frecency;
use crate::history::{fts_query, Place, PLACE_COLUMNS};
use crate::omnibox::{self, Navigation};
use crate::util::now_ms;
use crate::Result;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    /// Open the typed address.
    Visit,
    /// Search the engine for the typed text.
    Search,
    History,
    Bookmark,
    /// An open tab: switch to it instead of opening the page again.
    Tab,
    /// A search engine's suggestion.
    SearchSuggestion,
    /// A search the person made before.
    RecentSearch,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Suggestion {
    pub kind: Kind,
    pub title: String,
    pub url: String,
    /// The tab to switch to (`Kind::Tab`), else 0.
    pub tab_id: i64,
    /// For search rows: the engine and the query.
    pub engine: String,
    pub query: String,
    pub relevance: f64,
    /// The page's icon URL, when history has one (see favicons.rs).
    #[serde(default)]
    pub icon: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Suggestions {
    pub items: Vec<Suggestion>,
    /// The full inline completion (`example.com/`) when the typed text is
    /// a prefix of a frecent host; empty otherwise.
    pub autofill: String,
}

/// An open tab, for "switch to tab" rows.
#[derive(Debug, Clone)]
pub struct OpenTab {
    pub id: i64,
    pub url: String,
    pub title: String,
}

fn recent_row(query: &str, engine: &str, url: String) -> Suggestion {
    Suggestion {
        kind: Kind::RecentSearch,
        title: query.to_owned(),
        url,
        tab_id: 0,
        engine: engine.to_owned(),
        query: query.to_owned(),
        relevance: 0.0,
        icon: String::new(),
    }
}

/// Recent searches shown before typing, and among typed suggestions.
pub const MAX_RECENT_EMPTY: usize = 5;
pub const MAX_RECENT_TYPED: usize = 2;

/// How many rows of each kind at most.
pub const MAX_PAGES: usize = 6;
pub const MAX_TABS: usize = 2;
pub const MAX_REMOTE: usize = 4;

/// Whether typed text may be sent to the search engine for suggestions:
/// not in private tabs or when the person turned them off (the caller's
/// `enabled`), not for addresses, and not for text that looks private (an
/// `@`, a long run of digits, or more than 100 characters).
pub fn may_fetch_remote(text: &str, enabled: bool) -> bool {
    let t = text.trim();
    if !enabled || t.is_empty() || t.chars().count() > 100 || t.contains('@') {
        return false;
    }
    if omnibox::as_url(t).is_some() || t.contains("://") {
        return false;
    }
    let mut run = 0;
    for c in t.chars() {
        run = if c.is_ascii_digit() { run + 1 } else { 0 };
        if run >= 6 {
            return false;
        }
    }
    true
}

fn words(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(str::to_lowercase)
        .collect()
}

/// The topicality part of the relevance (see the module comment).
fn topicality(place: &Place, words: &[String], bookmarked: bool, input_uses: f64) -> f64 {
    let url = url::Url::parse(&place.url).ok();
    let host = place.host.to_lowercase();
    let path = url
        .as_ref()
        .map(|u| {
            format!(
                "{}{}",
                u.path(),
                u.query().map(|q| format!("?{q}")).unwrap_or_default()
            )
        })
        .unwrap_or_default()
        .to_lowercase();
    let title_words = self::words(&place.title);
    let mut t = 0.0;
    if let Some(first) = words.first() {
        if host.starts_with(first.as_str()) {
            t += 10.0;
        }
    }
    for w in words {
        if host.contains(w.as_str()) {
            t += 4.0;
        }
        if path.contains(w.as_str()) {
            t += 2.0;
        }
        if title_words.iter().any(|tw| tw.starts_with(w.as_str())) {
            t += 3.0;
        }
    }
    if place.typed_count > 0 {
        t += 2.0;
    }
    if bookmarked {
        t += 3.0;
    }
    t + 5.0 * input_uses.min(4.0)
}

impl Profile {
    #[allow(clippy::too_many_lines, reason = "one ranked list built in order")]
    /// Suggestions for `text`, without the engine's remote suggestions
    /// (add them with [`merge_remote`]).
    pub fn suggest(&self, text: &str, tabs: &[OpenTab]) -> Result<Suggestions> {
        let text = text.trim_start();
        let mut out = Suggestions::default();
        if text.trim().is_empty() {
            // Before anything is typed: the recent searches.
            let engines = self.search_engines()?;
            for r in self.recent_searches("", MAX_RECENT_EMPTY)? {
                let url = engines
                    .iter()
                    .find(|e| e.id == r.engine)
                    .map(|e| e.search_url_for(&r.query))
                    .unwrap_or_default();
                out.items.push(recent_row(&r.query, &r.engine, url));
            }
            return Ok(out);
        }
        let default = self.default_engine()?;
        let engines = self.search_engines()?;
        let nav = omnibox::classify(text, &default, &|k| {
            engines
                .iter()
                .find(|e| !e.keyword.is_empty() && e.keyword.eq_ignore_ascii_case(k))
                .cloned()
        });
        out.autofill = self.autofill(text)?;
        match nav {
            Some(Navigation::Url { url }) => out.items.push(Suggestion {
                kind: Kind::Visit,
                title: text.trim().to_owned(),
                url,
                tab_id: 0,
                engine: String::new(),
                query: String::new(),
                relevance: f64::MAX,
                icon: String::new(),
            }),
            Some(Navigation::Search { engine, query, url }) => {
                // With an autofill, Enter opens the completed host, so the
                // first row says so.
                if out.autofill.is_empty() {
                    out.items.push(Suggestion {
                        kind: Kind::Search,
                        title: query.clone(),
                        url,
                        tab_id: 0,
                        engine,
                        query,
                        relevance: f64::MAX,
                        icon: String::new(),
                    });
                } else {
                    let visit = omnibox::as_url(&out.autofill).unwrap_or_default();
                    out.items.push(Suggestion {
                        kind: Kind::Visit,
                        title: out.autofill.clone(),
                        url: visit,
                        tab_id: 0,
                        engine: String::new(),
                        query: String::new(),
                        relevance: f64::MAX,
                        icon: String::new(),
                    });
                    out.items.push(Suggestion {
                        kind: Kind::Search,
                        title: query.clone(),
                        url,
                        tab_id: 0,
                        engine,
                        query,
                        relevance: f64::MAX,
                        icon: String::new(),
                    });
                }
            }
            None => {}
        }
        let ws = words(text);
        let mut seen: HashSet<String> = out.items.iter().map(|s| s.url.clone()).collect();
        // Searches made before that start with the text.
        let typed_query = out
            .items
            .iter()
            .find(|i| i.kind == Kind::Search)
            .map(|i| i.query.to_lowercase());
        for r in self.recent_searches(text, MAX_RECENT_TYPED + 1)? {
            if Some(r.query.to_lowercase()) == typed_query
                || out
                    .items
                    .iter()
                    .filter(|i| i.kind == Kind::RecentSearch)
                    .count()
                    >= MAX_RECENT_TYPED
            {
                continue;
            }
            let url = engines
                .iter()
                .find(|e| e.id == r.engine)
                .map(|e| e.search_url_for(&r.query))
                .unwrap_or_default();
            seen.insert(url.clone());
            out.items.push(recent_row(&r.query, &r.engine, url));
        }
        for (place, relevance, bookmarked) in self.ranked_pages(text, &ws)? {
            if !seen.insert(place.url.clone()) {
                continue;
            }
            let title = if place.title.is_empty() {
                place.url.clone()
            } else {
                place.title.clone()
            };
            out.items.push(Suggestion {
                kind: if bookmarked {
                    Kind::Bookmark
                } else {
                    Kind::History
                },
                title,
                url: place.url,
                tab_id: 0,
                engine: String::new(),
                query: String::new(),
                relevance,
                icon: place.icon_url,
            });
            if out.items.len() >= MAX_PAGES + 2 {
                break;
            }
        }
        let mut tab_rows = 0;
        for tab in tabs {
            let hay = format!("{} {}", tab.title, tab.url).to_lowercase();
            if !ws.is_empty() && ws.iter().all(|w| hay.contains(w.as_str())) {
                out.items.push(Suggestion {
                    kind: Kind::Tab,
                    title: tab.title.clone(),
                    url: tab.url.clone(),
                    tab_id: tab.id,
                    engine: String::new(),
                    query: String::new(),
                    relevance: 0.0,
                    icon: self.icon_of(&tab.url).unwrap_or_default(),
                });
                tab_rows += 1;
                if tab_rows >= MAX_TABS {
                    break;
                }
            }
        }
        Ok(out)
    }

    /// History and bookmarked places matching every word, best first.
    fn ranked_pages(&self, text: &str, ws: &[String]) -> Result<Vec<(Place, f64, bool)>> {
        let Some(fts) = fts_query(text) else {
            return Ok(Vec::new());
        };
        let now = now_ms();
        let typed = text.trim().to_lowercase();
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT {PLACE_COLUMNS},
                EXISTS(SELECT 1 FROM bookmarks b WHERE b.url = p.url AND b.folder = 0),
                coalesce((SELECT max(i.use_count) FROM input_history i
                          WHERE i.place_id = p.id AND substr(i.input, 1, length(?2)) = ?2), 0)
             FROM places_fts f JOIN places p ON p.id = f.rowid
             WHERE places_fts MATCH ?1 AND (p.frecency > 0 OR p.visit_count > 0)
             ORDER BY p.frecency DESC LIMIT 60"
        ))?;
        let mut rows: Vec<(Place, f64, bool)> = stmt
            .query_map(params![fts, typed], |r| {
                let place = Place {
                    id: r.get(0)?,
                    url: r.get(1)?,
                    host: r.get(2)?,
                    title: r.get(3)?,
                    visit_count: r.get(4)?,
                    typed_count: r.get(5)?,
                    last_visit: r.get(6)?,
                    frecency: r.get(7)?,
                    icon_url: r.get(8)?,
                };
                let bookmarked: bool = r.get(9)?;
                let uses: f64 = r.get(10)?;
                Ok((place, bookmarked, uses))
            })?
            .map(|row| {
                row.map(|(place, bookmarked, uses)| {
                    let rel = (1.0 + frecency::score_at(place.frecency, now)).log2()
                        + topicality(&place, ws, bookmarked, uses);
                    (place, rel, bookmarked)
                })
            })
            .collect::<rusqlite::Result<_>>()?;
        rows.sort_by(|a, b| b.1.total_cmp(&a.1));
        rows.truncate(MAX_PAGES);
        Ok(rows)
    }

    /// The inline completion for `text`: the host (with a trailing `/`) of
    /// the most frecent place whose host starts with it, keeping the typed
    /// case; empty when none or when the text has a space or a path.
    pub fn autofill(&self, text: &str) -> Result<String> {
        let t = text.trim();
        if t.is_empty() || t.contains(char::is_whitespace) || t.contains('/') || t.contains(':') {
            return Ok(String::new());
        }
        let lower = t.to_lowercase();
        let prefix = lower.strip_prefix("www.").unwrap_or(&lower).to_owned();
        if prefix.is_empty() {
            return Ok(String::new());
        }
        let mut stmt = self.conn.prepare_cached(
            "SELECT host FROM places WHERE substr(host, 1, length(?1)) = ?1 AND frecency > 0
             ORDER BY frecency DESC LIMIT 1",
        )?;
        let host: Option<String> = stmt
            .query_map([&prefix], |r| r.get(0))?
            .next()
            .transpose()?;
        Ok(host.map_or(String::new(), |h| {
            // Keep what was typed and append the rest of the host.
            let typed_www = lower.starts_with("www.");
            let full = if typed_www { format!("www.{h}") } else { h };
            format!("{t}{}/", &full[t.len()..])
        }))
    }

    /// Learns that after typing `input` the person chose `url` (adaptive
    /// input history).
    pub fn record_selection(&self, input: &str, url: &str) -> Result<()> {
        let input = input.trim().to_lowercase();
        if input.is_empty() {
            return Ok(());
        }
        if let Some(id) = self.place_id(url)? {
            self.conn.execute(
                "INSERT INTO input_history(place_id, input, use_count) VALUES (?1, ?2, 1)
                 ON CONFLICT(place_id, input) DO UPDATE SET use_count = use_count + 1",
                params![id, input],
            )?;
        }
        Ok(())
    }

    /// Decays every input-history count by 10% and forgets the faded ones;
    /// the app calls it once a day.
    pub fn decay_input_history(&self) -> Result<()> {
        self.conn.execute_batch(
            "UPDATE input_history SET use_count = use_count * 0.9;
             DELETE FROM input_history WHERE use_count < 0.05;",
        )?;
        Ok(())
    }
}

/// Appends the engine's suggestions (already parsed) to `s`, skipping any
/// that repeat the first row's query.
pub fn merge_remote(
    s: &mut Suggestions,
    engine_id: &str,
    remote: &[String],
    engine: &crate::search::SearchEngine,
) {
    let first = s
        .items
        .first()
        .map(|i| i.query.to_lowercase())
        .unwrap_or_default();
    let mut n = 0;
    for q in remote {
        if q.to_lowercase() == first
            || s.items
                .iter()
                .any(|i| i.kind == Kind::SearchSuggestion && i.query == *q)
        {
            continue;
        }
        s.items.push(Suggestion {
            kind: Kind::SearchSuggestion,
            title: q.clone(),
            url: engine.search_url_for(q),
            tab_id: 0,
            engine: engine_id.to_owned(),
            query: q.clone(),
            relevance: 0.0,
            icon: String::new(),
        });
        n += 1;
        if n >= MAX_REMOTE {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bookmarks::ROOT;
    use crate::frecency::Transition;

    const DAY: i64 = 24 * 3600 * 1000;

    fn kinds(s: &Suggestions) -> Vec<(Kind, String)> {
        s.items.iter().map(|i| (i.kind, i.url.clone())).collect()
    }

    #[test]
    fn heuristic_row_comes_first() {
        let p = Profile::in_memory().unwrap();
        let s = p.suggest("rust lang", &[]).unwrap();
        assert_eq!(s.items[0].kind, Kind::Search);
        assert_eq!(s.items[0].url, "https://duckduckgo.com/?q=rust+lang");
        let s = p.suggest("example.com", &[]).unwrap();
        assert_eq!(s.items[0].kind, Kind::Visit);
        assert_eq!(s.items[0].url, "https://example.com/");
        assert!(p.suggest("  ", &[]).unwrap().items.is_empty());
        p.record_search("rust book", "duckduckgo", 5).unwrap();
        let empty = p.suggest("", &[]).unwrap();
        assert_eq!(empty.items[0].kind, Kind::RecentSearch);
        assert_eq!(empty.items[0].url, "https://duckduckgo.com/?q=rust+book");
        let typed = p.suggest("rust", &[]).unwrap();
        assert_eq!(typed.items[0].kind, Kind::Search);
        assert_eq!(typed.items[1].kind, Kind::RecentSearch);
        // Not repeated when it is what was typed.
        let same = p.suggest("rust book", &[]).unwrap();
        assert!(!same.items.iter().any(|i| i.kind == Kind::RecentSearch));
    }

    #[test]
    fn ranks_frecent_and_topical_pages() {
        let p = Profile::in_memory().unwrap();
        let now = now_ms();
        // Visited often, recently, typed.
        for i in 0..20 {
            p.record_visit(
                "https://news.example.com/",
                Some("Example News"),
                Transition::Typed,
                now - i * DAY,
            )
            .unwrap();
        }
        // Visited once, long ago.
        p.record_visit(
            "https://old.example.org/news",
            Some("Old news archive"),
            Transition::Link,
            now - 300 * DAY,
        )
        .unwrap();
        // (Two words: no inline completion takes the first page.)
        let s = p.suggest("example news", &[]).unwrap();
        let pages: Vec<_> = s
            .items
            .iter()
            .filter(|i| i.kind == Kind::History)
            .map(|i| i.url.as_str())
            .collect();
        assert_eq!(
            pages,
            ["https://news.example.com/", "https://old.example.org/news"]
        );
        // Every word must match.
        let s = p.suggest("news archive", &[]).unwrap();
        let pages: Vec<_> = s
            .items
            .iter()
            .filter(|i| i.kind == Kind::History)
            .map(|i| i.url.as_str())
            .collect();
        assert_eq!(pages, ["https://old.example.org/news"]);
    }

    #[test]
    fn input_history_promotes_a_chosen_page() {
        let p = Profile::in_memory().unwrap();
        let now = now_ms();
        for i in 0..5 {
            p.record_visit(
                "https://docs.example.com/guide",
                Some("Guide"),
                Transition::Link,
                now - i * DAY,
            )
            .unwrap();
        }
        p.record_visit(
            "https://dogs.example.net/",
            Some("Dogs"),
            Transition::Link,
            now - 5 * DAY,
        )
        .unwrap();
        let first = |p: &Profile| {
            p.suggest("exam", &[])
                .unwrap()
                .items
                .into_iter()
                .find(|i| i.kind == Kind::History)
                .unwrap()
                .url
        };
        assert_eq!(first(&p), "https://docs.example.com/guide");
        for _ in 0..3 {
            p.record_selection("example", "https://dogs.example.net/")
                .unwrap();
        }
        assert_eq!(first(&p), "https://dogs.example.net/");
        // Input history decays.
        for _ in 0..60 {
            p.decay_input_history().unwrap();
        }
        assert_eq!(first(&p), "https://docs.example.com/guide");
    }

    #[test]
    fn bookmarks_and_tabs() {
        let p = Profile::in_memory().unwrap();
        p.add_bookmark("https://sailfishos.org/", "Sailfish OS", ROOT)
            .unwrap();
        let tabs = [OpenTab {
            id: 7,
            url: "https://forum.sailfishos.org/".into(),
            title: "Sailfish forum".into(),
        }];
        let s = p.suggest("sailfish os", &tabs).unwrap();
        let k = kinds(&s);
        assert!(k.contains(&(Kind::Bookmark, "https://sailfishos.org/".into())));
        let tab = s.items.iter().find(|i| i.kind == Kind::Tab).unwrap();
        assert_eq!(tab.tab_id, 7);
        assert_eq!(tab.icon, "");
        // A tab whose page has an icon in history shows it.
        p.record_visit(
            "https://forum.sailfishos.org/",
            Some("Sailfish forum"),
            Transition::Link,
            now_ms(),
        )
        .unwrap();
        p.set_icon(
            "https://forum.sailfishos.org/",
            "https://forum.sailfishos.org/icon.png",
        )
        .unwrap();
        let s = p.suggest("sailfish os", &tabs).unwrap();
        let tab = s.items.iter().find(|i| i.kind == Kind::Tab).unwrap();
        assert_eq!(tab.icon, "https://forum.sailfishos.org/icon.png");
    }

    #[test]
    fn autofill_completes_hosts() {
        let p = Profile::in_memory().unwrap();
        let now = now_ms();
        p.record_visit(
            "https://www.example.com/deep/page",
            Some("x"),
            Transition::Typed,
            now,
        )
        .unwrap();
        p.record_visit(
            "https://exhibit.org/",
            Some("y"),
            Transition::Link,
            now - 100 * DAY,
        )
        .unwrap();
        assert_eq!(p.autofill("exa").unwrap(), "example.com/");
        assert_eq!(p.autofill("Ex").unwrap(), "Example.com/");
        assert_eq!(p.autofill("www.exa").unwrap(), "www.example.com/");
        assert_eq!(p.autofill("exh").unwrap(), "exhibit.org/");
        assert_eq!(p.autofill("exa mple").unwrap(), "");
        assert_eq!(p.autofill("zzz").unwrap(), "");
        let s = p.suggest("exa", &[]).unwrap();
        assert_eq!(s.autofill, "example.com/");
        assert_eq!(s.items[0].kind, Kind::Visit);
        assert_eq!(s.items[0].url, "https://example.com/");
        assert_eq!(s.items[1].kind, Kind::Search);
    }

    #[test]
    fn remote_suggestions_merge_and_privacy() {
        let p = Profile::in_memory().unwrap();
        let mut s = p.suggest("rust", &[]).unwrap();
        let engine = p.default_engine().unwrap();
        merge_remote(
            &mut s,
            &engine.id,
            &["Rust".into(), "rust lang".into(), "rustup".into()],
            &engine,
        );
        let remote: Vec<_> = s
            .items
            .iter()
            .filter(|i| i.kind == Kind::SearchSuggestion)
            .map(|i| i.query.as_str())
            .collect();
        assert_eq!(remote, ["rust lang", "rustup"]);
        assert!(may_fetch_remote("rust lang", true));
        assert!(!may_fetch_remote("rust lang", false));
        assert!(!may_fetch_remote("me@example.com", true));
        assert!(!may_fetch_remote("card 4111111111111111", true));
        assert!(!may_fetch_remote("example.com", true));
        assert!(!may_fetch_remote(&"x".repeat(101), true));
    }
}
