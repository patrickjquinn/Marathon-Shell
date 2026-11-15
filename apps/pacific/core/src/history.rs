// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Browsing history: places (one row per URL) and their visits.

use rusqlite::{params, OptionalExtension};
use serde::Serialize;

use crate::db::Profile;
use crate::frecency::{self, Transition};
use crate::util::{display_host, now_ms};
use crate::Result;

/// [`frecency::SAMPLE`] as an SQL parameter.
const SAMPLE: i64 = 10;
const _: () = assert!(frecency::SAMPLE == 10);

/// A page in history.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Place {
    pub id: i64,
    pub url: String,
    pub host: String,
    pub title: String,
    pub visit_count: i64,
    pub typed_count: i64,
    pub last_visit: i64,
    pub frecency: f64,
    pub icon_url: String,
}

impl Place {
    fn from_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            id: r.get(0)?,
            url: r.get(1)?,
            host: r.get(2)?,
            title: r.get(3)?,
            visit_count: r.get(4)?,
            typed_count: r.get(5)?,
            last_visit: r.get(6)?,
            frecency: r.get(7)?,
            icon_url: r.get(8)?,
        })
    }
}

pub(crate) const PLACE_COLUMNS: &str =
    "p.id, p.url, p.host, p.title, p.visit_count, p.typed_count, p.last_visit, p.frecency, p.icon_url";

/// Whether a URL belongs in history: web pages only (no `about:`, `data:`,
/// `file:` or reader-mode pages, no `javascript:`), and not too long.
pub fn is_storable(url: &str) -> bool {
    url.len() <= 8192 && url::Url::parse(url).is_ok_and(|u| matches!(u.scheme(), "http" | "https"))
}

impl Profile {
    /// Records a visit to `url` at `at_ms` and recomputes its frecency.
    /// Returns the place id, or `None` when the URL is not stored (see
    /// [`is_storable`]). Redirect sources are recorded as visits but do not
    /// raise the visit count.
    pub fn record_visit(
        &self,
        url: &str,
        title: Option<&str>,
        transition: Transition,
        at_ms: i64,
    ) -> Result<Option<i64>> {
        if !is_storable(url) {
            return Ok(None);
        }
        let host = display_host(url);
        let counts = i64::from(!matches!(
            transition,
            Transition::RedirectSource | Transition::Download
        ));
        let typed = i64::from(transition == Transition::Typed);
        let id: i64 = self.conn.query_row(
            "INSERT INTO places(url, host, title, visit_count, typed_count, last_visit)
             VALUES (?1, ?2, coalesce(?3, ''), ?4, ?5, ?6)
             ON CONFLICT(url) DO UPDATE SET
                visit_count = visit_count + excluded.visit_count,
                typed_count = typed_count + excluded.typed_count,
                last_visit = max(last_visit, excluded.last_visit),
                title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE title END
             RETURNING id",
            params![url, host, title, counts, typed, at_ms],
            |r| r.get(0),
        )?;
        self.conn.execute(
            "INSERT INTO visits(place_id, visited_at, transition) VALUES (?1, ?2, ?3)",
            params![id, at_ms, transition.to_i64()],
        )?;
        self.update_frecency(id, at_ms)?;
        Ok(Some(id))
    }

    /// Recomputes and stores the frecency of place `id` (frecency.rs).
    pub fn update_frecency(&self, id: i64, now: i64) -> Result<()> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT visited_at, transition FROM visits WHERE place_id = ?1
             ORDER BY visited_at DESC LIMIT ?2",
        )?;
        let visits: Vec<(i64, Transition)> = stmt
            .query_map(params![id, SAMPLE], |r| {
                Ok((r.get(0)?, Transition::from_i64(r.get(1)?)))
            })?
            .collect::<rusqlite::Result<_>>()?;
        let (count, url): (i64, String) = self.conn.query_row(
            "SELECT visit_count, url FROM places WHERE id = ?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        let bookmarked = self.is_bookmarked(&url)?;
        let s = frecency::score(&visits, count, bookmarked, now);
        self.conn.execute(
            "UPDATE places SET frecency = ?2 WHERE id = ?1",
            params![id, frecency::to_date(s, now)],
        )?;
        Ok(())
    }

    /// Recomputes the frecency of `url` if it is in history (after a
    /// bookmark change).
    pub fn refresh_frecency_of(&self, url: &str) -> Result<()> {
        if let Some(id) = self.place_id(url)? {
            self.update_frecency(id, now_ms())?;
        } else if self.is_bookmarked(url)? && is_storable(url) {
            // A bookmark of a page never visited: give it a place so it
            // ranks in the address bar.
            let title = self.bookmark_for(url)?.map(|b| b.title).unwrap_or_default();
            self.conn.execute(
                "INSERT OR IGNORE INTO places(url, host, title) VALUES (?1, ?2, ?3)",
                params![url, display_host(url), title],
            )?;
            if let Some(id) = self.place_id(url)? {
                self.update_frecency(id, now_ms())?;
            }
        }
        Ok(())
    }

    pub fn place_id(&self, url: &str) -> Result<Option<i64>> {
        Ok(self
            .conn
            .query_row("SELECT id FROM places WHERE url = ?1", [url], |r| r.get(0))
            .optional()?)
    }

    pub fn place(&self, url: &str) -> Result<Option<Place>> {
        Ok(self
            .conn
            .query_row(
                &format!("SELECT {PLACE_COLUMNS} FROM places p WHERE p.url = ?1"),
                [url],
                Place::from_row,
            )
            .optional()?)
    }

    pub fn place_by_id(&self, id: i64) -> Result<Option<Place>> {
        Ok(self
            .conn
            .query_row(
                &format!("SELECT {PLACE_COLUMNS} FROM places p WHERE p.id = ?1"),
                [id],
                Place::from_row,
            )
            .optional()?)
    }

    /// Sets the page title once the page has one.
    pub fn set_title(&self, url: &str, title: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE places SET title = ?2 WHERE url = ?1 AND title <> ?2",
            params![url, title],
        )?;
        Ok(())
    }

    /// The icon recorded for a page, if any (for open tabs in suggestions).
    pub fn icon_of(&self, url: &str) -> Result<String> {
        use rusqlite::OptionalExtension;
        let icon: Option<String> = self
            .conn
            .query_row(
                "SELECT icon_url FROM places WHERE url = ?1",
                params![url],
                |r| r.get(0),
            )
            .optional()?;
        Ok(icon.unwrap_or_default())
    }

    pub fn set_icon(&self, url: &str, icon_url: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE places SET icon_url = ?2 WHERE url = ?1",
            params![url, icon_url],
        )?;
        Ok(())
    }

    /// History, newest first: `query` empty lists everything, otherwise a
    /// full-text match over titles and URLs. `since_ms` limits to pages
    /// visited at or after it (0: no limit).
    pub fn history(
        &self,
        query: &str,
        since_ms: i64,
        limit: usize,
        offset: usize,
    ) -> Result<Vec<Place>> {
        let limit = i64::try_from(limit).unwrap_or(i64::MAX);
        let offset = i64::try_from(offset).unwrap_or(0);
        let fts = fts_query(query);
        let rows = if let Some(fts) = fts {
            let mut stmt = self.conn.prepare_cached(&format!(
                "SELECT {PLACE_COLUMNS} FROM places_fts f JOIN places p ON p.id = f.rowid
                 WHERE places_fts MATCH ?1 AND p.visit_count > 0 AND p.last_visit >= ?2
                 ORDER BY p.last_visit DESC LIMIT ?3 OFFSET ?4"
            ))?;
            let rows = stmt
                .query_map(params![fts, since_ms, limit, offset], Place::from_row)?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            rows
        } else {
            let mut stmt = self.conn.prepare_cached(&format!(
                "SELECT {PLACE_COLUMNS} FROM places p
                 WHERE p.visit_count > 0 AND p.last_visit >= ?1
                 ORDER BY p.last_visit DESC LIMIT ?2 OFFSET ?3"
            ))?;
            let rows = stmt
                .query_map(params![since_ms, limit, offset], Place::from_row)?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            rows
        };
        Ok(rows)
    }

    /// The most frecent pages for the new-tab page: one per site name (a
    /// tile is labelled with it, so bbc.com and bbc.co.uk were two "bbc"
    /// tiles), without pages the person removed from top sites.
    pub fn top_sites(&self, limit: usize) -> Result<Vec<Place>> {
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT {PLACE_COLUMNS} FROM places p
             WHERE p.hidden = 0 AND p.frecency > 0 AND p.visit_count > 0
             ORDER BY p.frecency DESC LIMIT 200"
        ))?;
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for place in stmt.query_map([], Place::from_row)? {
            let place = place?;
            if seen.insert(crate::util::site_name(&place.host)) {
                out.push(place);
                if out.len() >= limit {
                    break;
                }
            }
        }
        Ok(out)
    }

    /// Takes a page off the new-tab page's top sites (it stays in history).
    pub fn hide_top_site(&self, url: &str) -> Result<()> {
        self.conn
            .execute("UPDATE places SET hidden = 1 WHERE url = ?1", [url])?;
        Ok(())
    }

    /// Deletes one page from history (its visits and input history too).
    /// A bookmarked page keeps its place row without visits.
    pub fn delete_place(&self, url: &str) -> Result<()> {
        if self.is_bookmarked(url)? {
            if let Some(id) = self.place_id(url)? {
                self.conn
                    .execute("DELETE FROM visits WHERE place_id = ?1", [id])?;
                self.conn
                    .execute("DELETE FROM input_history WHERE place_id = ?1", [id])?;
                self.conn.execute(
                    "UPDATE places SET visit_count = 0, typed_count = 0, last_visit = 0 WHERE id = ?1",
                    [id],
                )?;
                self.update_frecency(id, now_ms())?;
            }
        } else {
            self.conn
                .execute("DELETE FROM places WHERE url = ?1", [url])?;
        }
        Ok(())
    }

    /// Deletes every visit in `[from_ms, to_ms)`, then the places left
    /// without visits (bookmarked ones stay), and recomputes the rest.
    pub fn delete_visits_between(&self, from_ms: i64, to_ms: i64) -> Result<usize> {
        let tx = self.conn.unchecked_transaction()?;
        let affected: Vec<i64> = {
            let mut stmt = tx.prepare(
                "SELECT DISTINCT place_id FROM visits WHERE visited_at >= ?1 AND visited_at < ?2",
            )?;
            let rows = stmt
                .query_map(params![from_ms, to_ms], |r| r.get(0))?
                .collect::<rusqlite::Result<_>>()?;
            rows
        };
        let n = tx.execute(
            "DELETE FROM visits WHERE visited_at >= ?1 AND visited_at < ?2",
            params![from_ms, to_ms],
        )?;
        for id in &affected {
            tx.execute(
                "UPDATE places SET
                    visit_count = (SELECT count(*) FROM visits WHERE place_id = ?1 AND transition NOT IN (6, 7)),
                    typed_count = (SELECT count(*) FROM visits WHERE place_id = ?1 AND transition = 1),
                    last_visit = coalesce((SELECT max(visited_at) FROM visits WHERE place_id = ?1), 0)
                 WHERE id = ?1",
                [id],
            )?;
        }
        tx.execute(
            "DELETE FROM places WHERE NOT EXISTS (SELECT 1 FROM visits v WHERE v.place_id = places.id)
             AND NOT EXISTS (SELECT 1 FROM bookmarks b WHERE b.url = places.url)",
            [],
        )?;
        tx.commit()?;
        let now = now_ms();
        for id in affected {
            if self.place_by_id(id)?.is_some() {
                self.update_frecency(id, now)?;
            }
        }
        Ok(n)
    }

    /// Forgets visits older than `days` (history retention), keeping each
    /// place's newest visits so frecency still has a sample.
    pub fn expire_visits(&self, days: i64, now: i64) -> Result<usize> {
        let cutoff = now - days * 24 * 3600 * 1000;
        let n = self.conn.execute(
            "DELETE FROM visits WHERE visited_at < ?1 AND id NOT IN (
                SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY place_id ORDER BY visited_at DESC) AS rn FROM visits) WHERE rn <= ?2)",
            params![cutoff, SAMPLE],
        )?;
        Ok(n)
    }

    /// Visits of one page, newest first (for the history page's details).
    pub fn visits_of(&self, url: &str, limit: usize) -> Result<Vec<(i64, Transition)>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT v.visited_at, v.transition FROM visits v JOIN places p ON p.id = v.place_id
             WHERE p.url = ?1 ORDER BY v.visited_at DESC LIMIT ?2",
        )?;
        let rows = stmt
            .query_map(
                params![url, i64::try_from(limit).unwrap_or(i64::MAX)],
                |r| Ok((r.get(0)?, Transition::from_i64(r.get(1)?))),
            )?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }
}

/// An FTS5 query from typed text: every word as a quoted prefix term,
/// all required. `None` for text without words.
pub fn fts_query(text: &str) -> Option<String> {
    let terms: Vec<String> = text
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .take(8)
        .map(|w| format!("\"{}\"*", w.to_lowercase()))
        .collect();
    (!terms.is_empty()).then(|| terms.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAY: i64 = 24 * 3600 * 1000;

    #[test]
    fn records_visits_and_counts() {
        let p = Profile::in_memory().unwrap();
        let t0 = 100 * DAY;
        let id = p
            .record_visit(
                "https://www.example.com/a",
                Some("Example A"),
                Transition::Typed,
                t0,
            )
            .unwrap()
            .unwrap();
        p.record_visit(
            "https://www.example.com/a",
            None,
            Transition::Link,
            t0 + 1000,
        )
        .unwrap();
        let place = p.place_by_id(id).unwrap().unwrap();
        assert_eq!(place.visit_count, 2);
        assert_eq!(place.typed_count, 1);
        assert_eq!(place.title, "Example A");
        assert_eq!(place.host, "example.com");
        assert_eq!(place.last_visit, t0 + 1000);
        assert!(place.frecency > 0.0);
        assert_eq!(
            p.visits_of("https://www.example.com/a", 10).unwrap().len(),
            2
        );
    }

    #[test]
    fn non_web_urls_are_not_stored() {
        let p = Profile::in_memory().unwrap();
        for u in [
            "about:blank",
            "data:text/html,x",
            "file:///etc/passwd",
            "javascript:alert(1)",
        ] {
            assert_eq!(p.record_visit(u, None, Transition::Typed, 1).unwrap(), None);
        }
    }

    #[test]
    fn full_text_search_and_since() {
        let p = Profile::in_memory().unwrap();
        p.record_visit(
            "https://rust-lang.org/",
            Some("Rust Programming Language"),
            Transition::Link,
            10 * DAY,
        )
        .unwrap();
        p.record_visit(
            "https://sailfishos.org/",
            Some("Sailfish OS"),
            Transition::Link,
            20 * DAY,
        )
        .unwrap();
        assert_eq!(p.history("", 0, 10, 0).unwrap().len(), 2);
        let r = p.history("progr", 0, 10, 0).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].url, "https://rust-lang.org/");
        // URL words match too, and diacritics are folded.
        assert_eq!(p.history("sailfishos", 0, 10, 0).unwrap().len(), 1);
        p.set_title("https://sailfishos.org/", "Sàilfish").unwrap();
        assert_eq!(p.history("sailfish", 0, 10, 0).unwrap().len(), 1);
        assert_eq!(p.history("", 15 * DAY, 10, 0).unwrap().len(), 1);
        assert_eq!(p.history("+++", 0, 10, 0).unwrap().len(), 2);
    }

    #[test]
    fn top_sites_one_per_host_without_hidden() {
        let p = Profile::in_memory().unwrap();
        let now = 50 * DAY;
        for i in 0..5 {
            p.record_visit("https://a.example/1", None, Transition::Typed, now - i)
                .unwrap();
        }
        p.record_visit("https://a.example/2", None, Transition::Typed, now)
            .unwrap();
        p.record_visit("https://b.example/", None, Transition::Link, now)
            .unwrap();
        let top = p.top_sites(10).unwrap();
        assert_eq!(
            top.iter().map(|t| t.url.as_str()).collect::<Vec<_>>(),
            ["https://a.example/1", "https://b.example/"]
        );
        p.hide_top_site("https://a.example/1").unwrap();
        assert_eq!(p.top_sites(10).unwrap()[0].url, "https://a.example/2");
    }

    #[test]
    fn top_sites_one_per_site_name() {
        let p = Profile::in_memory().unwrap();
        let now = 50 * DAY;
        for i in 0..3 {
            p.record_visit(
                "https://www.bbc.co.uk/news",
                None,
                Transition::Typed,
                now - i,
            )
            .unwrap();
        }
        p.record_visit("https://www.bbc.com/", None, Transition::Link, now)
            .unwrap();
        p.record_visit(
            "https://en.wikipedia.org/wiki/A",
            None,
            Transition::Link,
            now,
        )
        .unwrap();
        p.record_visit(
            "https://en.m.wikipedia.org/wiki/B",
            None,
            Transition::Link,
            now,
        )
        .unwrap();
        let top = p.top_sites(10).unwrap();
        let names: Vec<_> = top
            .iter()
            .map(|t| crate::util::site_name(&t.host))
            .collect();
        assert_eq!(top.len(), 2, "{names:?}");
        assert_eq!(top[0].url, "https://www.bbc.co.uk/news");
    }

    #[test]
    fn delete_by_range_and_place() {
        let p = Profile::in_memory().unwrap();
        p.record_visit("https://old.example/", None, Transition::Link, DAY)
            .unwrap();
        p.record_visit("https://both.example/", None, Transition::Link, DAY)
            .unwrap();
        p.record_visit("https://both.example/", None, Transition::Link, 10 * DAY)
            .unwrap();
        p.record_visit("https://new.example/", None, Transition::Link, 10 * DAY)
            .unwrap();
        assert_eq!(p.delete_visits_between(0, 5 * DAY).unwrap(), 2);
        assert!(p.place("https://old.example/").unwrap().is_none());
        let both = p.place("https://both.example/").unwrap().unwrap();
        assert_eq!(both.visit_count, 1);
        assert_eq!(both.last_visit, 10 * DAY);
        p.delete_place("https://new.example/").unwrap();
        assert!(p.place("https://new.example/").unwrap().is_none());
        // The FTS index followed the deletes.
        assert_eq!(p.history("new", 0, 10, 0).unwrap().len(), 0);
    }

    #[test]
    fn expiry_keeps_a_sample() {
        let p = Profile::in_memory().unwrap();
        for i in 0..15 {
            p.record_visit("https://a.example/", None, Transition::Link, i * DAY)
                .unwrap();
        }
        let removed = p.expire_visits(1, 400 * DAY).unwrap();
        assert_eq!(removed, 5);
        assert_eq!(p.visits_of("https://a.example/", 100).unwrap().len(), 10);
    }

    #[test]
    fn fts_query_quotes_words() {
        assert_eq!(
            fts_query("Foo bar-baz").as_deref(),
            Some("\"foo\"* \"bar\"* \"baz\"*")
        );
        assert_eq!(fts_query("  \"' "), None);
    }
}
