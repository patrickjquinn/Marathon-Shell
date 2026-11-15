// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Recent searches: what the person searched for from the address bar,
//! offered again (newest first) before anything is typed and when what is
//! typed starts one. Never recorded for private tabs (their profile is in
//! memory and thrown away).

use rusqlite::params;
use serde::Serialize;

use crate::db::Profile;
use crate::Result;

/// Searches kept.
pub const MAX_KEPT: i64 = 200;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RecentSearch {
    pub query: String,
    pub engine: String,
    pub used: i64,
}

impl Profile {
    pub fn record_search(&self, query: &str, engine: &str, now_ms: i64) -> Result<()> {
        let q = query.trim();
        if q.is_empty() || q.chars().count() > 300 {
            return Ok(());
        }
        self.conn.execute(
            "INSERT INTO searches(query, engine, used) VALUES (?1, ?2, ?3)
             ON CONFLICT(query) DO UPDATE SET engine = excluded.engine, used = excluded.used, count = count + 1",
            params![q, engine, now_ms],
        )?;
        self.conn.execute(
            "DELETE FROM searches WHERE query NOT IN (SELECT query FROM searches ORDER BY used DESC LIMIT ?1)",
            [MAX_KEPT],
        )?;
        Ok(())
    }

    /// Recent searches starting with `prefix` (case-insensitive; all when
    /// empty), newest first.
    pub fn recent_searches(&self, prefix: &str, limit: usize) -> Result<Vec<RecentSearch>> {
        let p = prefix.trim().to_lowercase();
        let mut stmt = self.conn.prepare_cached(
            "SELECT query, engine, used FROM searches
             WHERE substr(lower(query), 1, length(?1)) = ?1 ORDER BY used DESC LIMIT ?2",
        )?;
        let rows = stmt
            .query_map(params![p, i64::try_from(limit).unwrap_or(i64::MAX)], |r| {
                Ok(RecentSearch {
                    query: r.get(0)?,
                    engine: r.get(1)?,
                    used: r.get(2)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    pub fn delete_search(&self, query: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM searches WHERE query = ?1", [query])?;
        Ok(())
    }

    /// Forgets searches made at or after `since_ms`.
    pub fn clear_searches_since(&self, since_ms: i64) -> Result<usize> {
        Ok(self
            .conn
            .execute("DELETE FROM searches WHERE used >= ?1", [since_ms])?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recent_first_prefix_and_clearing() {
        let p = Profile::in_memory().unwrap();
        p.record_search("sailfish os", "duckduckgo", 10).unwrap();
        p.record_search("rust lang", "duckduckgo", 20).unwrap();
        p.record_search("Sailfish forum", "duckduckgo", 30).unwrap();
        p.record_search("  ", "duckduckgo", 40).unwrap();
        let all: Vec<_> = p
            .recent_searches("", 10)
            .unwrap()
            .into_iter()
            .map(|s| s.query)
            .collect();
        assert_eq!(all, ["Sailfish forum", "rust lang", "sailfish os"]);
        let s: Vec<_> = p
            .recent_searches("sail", 10)
            .unwrap()
            .into_iter()
            .map(|s| s.query)
            .collect();
        assert_eq!(s, ["Sailfish forum", "sailfish os"]);
        p.record_search("sailfish os", "wikipedia", 50).unwrap();
        assert_eq!(p.recent_searches("", 1).unwrap()[0].engine, "wikipedia");
        p.delete_search("rust lang").unwrap();
        assert_eq!(p.clear_searches_since(40).unwrap(), 1);
        assert_eq!(p.recent_searches("", 10).unwrap().len(), 1);
        for i in 0..250 {
            p.record_search(&format!("q{i}"), "d", 100 + i).unwrap();
        }
        assert_eq!(
            p.recent_searches("", 1000).unwrap().len(),
            usize::try_from(MAX_KEPT).unwrap()
        );
    }
}
