// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The profile database: one SQLite file (`places.db`, WAL) holding history,
//! bookmarks, adaptive input history, site settings, downloads, search
//! engines, HTTPS-first exceptions and blocking totals.
//!
//! A private window uses [`Profile::in_memory`], which has the same schema
//! and is gone when dropped: nothing a private tab does touches the disk.

use std::path::{Path, PathBuf};

use rusqlite::Connection;

use crate::{Error, Result};

/// Schema version (`PRAGMA user_version`).
const VERSION: i32 = 2;

const SCHEMA: &str = r"
CREATE TABLE IF NOT EXISTS places(
    id INTEGER PRIMARY KEY,
    url TEXT NOT NULL UNIQUE,
    host TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    visit_count INTEGER NOT NULL DEFAULT 0,
    typed_count INTEGER NOT NULL DEFAULT 0,
    last_visit INTEGER NOT NULL DEFAULT 0,
    -- Exponential-decay frecency stored as a date (frecency.rs).
    frecency REAL NOT NULL DEFAULT 0,
    -- Removed from top sites by the person.
    hidden INTEGER NOT NULL DEFAULT 0,
    icon_url TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS places_frecency ON places(frecency DESC);
CREATE INDEX IF NOT EXISTS places_host ON places(host);
CREATE INDEX IF NOT EXISTS places_last_visit ON places(last_visit DESC);

CREATE TABLE IF NOT EXISTS visits(
    id INTEGER PRIMARY KEY,
    place_id INTEGER NOT NULL REFERENCES places(id) ON DELETE CASCADE,
    visited_at INTEGER NOT NULL,
    transition INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS visits_place ON visits(place_id, visited_at DESC);
CREATE INDEX IF NOT EXISTS visits_time ON visits(visited_at);

CREATE VIRTUAL TABLE IF NOT EXISTS places_fts USING fts5(
    title, url, content='places', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2', prefix='1 2 3'
);
CREATE TRIGGER IF NOT EXISTS places_ai AFTER INSERT ON places BEGIN
    INSERT INTO places_fts(rowid, title, url) VALUES (new.id, new.title, new.url);
END;
CREATE TRIGGER IF NOT EXISTS places_ad AFTER DELETE ON places BEGIN
    INSERT INTO places_fts(places_fts, rowid, title, url) VALUES ('delete', old.id, old.title, old.url);
END;
CREATE TRIGGER IF NOT EXISTS places_au AFTER UPDATE OF title, url ON places BEGIN
    INSERT INTO places_fts(places_fts, rowid, title, url) VALUES ('delete', old.id, old.title, old.url);
    INSERT INTO places_fts(rowid, title, url) VALUES (new.id, new.title, new.url);
END;

-- Firefox's moz_inputhistory: what was typed before a result was chosen.
CREATE TABLE IF NOT EXISTS input_history(
    place_id INTEGER NOT NULL REFERENCES places(id) ON DELETE CASCADE,
    input TEXT NOT NULL,
    use_count REAL NOT NULL,
    PRIMARY KEY(place_id, input)
);

CREATE TABLE IF NOT EXISTS bookmarks(
    id INTEGER PRIMARY KEY,
    parent INTEGER REFERENCES bookmarks(id) ON DELETE CASCADE,
    folder INTEGER NOT NULL DEFAULT 0,
    title TEXT NOT NULL DEFAULT '',
    url TEXT NOT NULL DEFAULT '',
    position INTEGER NOT NULL DEFAULT 0,
    added INTEGER NOT NULL,
    modified INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS bookmarks_parent ON bookmarks(parent, position);
CREATE INDEX IF NOT EXISTS bookmarks_url ON bookmarks(url);

CREATE TABLE IF NOT EXISTS site_settings(
    host TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    modified INTEGER NOT NULL,
    PRIMARY KEY(host, key)
);

CREATE TABLE IF NOT EXISTS downloads(
    id INTEGER PRIMARY KEY,
    url TEXT NOT NULL,
    path TEXT NOT NULL,
    mime TEXT NOT NULL DEFAULT '',
    total INTEGER NOT NULL DEFAULT -1,
    received INTEGER NOT NULL DEFAULT 0,
    state INTEGER NOT NULL,
    error TEXT NOT NULL DEFAULT '',
    started INTEGER NOT NULL,
    finished INTEGER NOT NULL DEFAULT 0,
    referrer TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS search_engines(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    keyword TEXT NOT NULL DEFAULT '',
    search_url TEXT NOT NULL,
    suggest_url TEXT NOT NULL DEFAULT '',
    suggest_format TEXT NOT NULL DEFAULT 'opensearch',
    position INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS https_exceptions(
    host TEXT PRIMARY KEY,
    added INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS blocked_daily(
    day INTEGER NOT NULL,
    kind TEXT NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY(day, kind)
);

-- Searches made from the address bar (recent searches); version 2.
CREATE TABLE IF NOT EXISTS searches(
    query TEXT PRIMARY KEY,
    engine TEXT NOT NULL,
    used INTEGER NOT NULL,
    count INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS searches_used ON searches(used DESC);

CREATE TABLE IF NOT EXISTS prefs(
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
";

/// An open profile database.
pub struct Profile {
    pub(crate) conn: Connection,
    path: Option<PathBuf>,
}

impl std::fmt::Debug for Profile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Profile")
            .field("path", &self.path)
            .finish_non_exhaustive()
    }
}

impl Profile {
    /// Opens (creating) `dir/places.db`.
    pub fn open(dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(dir).map_err(|e| Error::io(dir, e))?;
        let path = dir.join("places.db");
        let conn = Connection::open(&path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        let mut p = Self {
            conn,
            path: Some(path),
        };
        p.init()?;
        Ok(p)
    }

    /// A profile that lives in memory only (private browsing, tests).
    pub fn in_memory() -> Result<Self> {
        let mut p = Self {
            conn: Connection::open_in_memory()?,
            path: None,
        };
        p.init()?;
        Ok(p)
    }

    pub fn is_ephemeral(&self) -> bool {
        self.path.is_none()
    }

    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref()
    }

    fn init(&mut self) -> Result<()> {
        self.conn.pragma_update(None, "foreign_keys", "ON")?;
        self.conn.busy_timeout(std::time::Duration::from_secs(5))?;
        let version: i32 = self
            .conn
            .pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version > VERSION {
            return Err(Error::Invalid(format!(
                "profile database version {version} is newer than this Pacific ({VERSION})"
            )));
        }
        let tx = self.conn.transaction()?;
        tx.execute_batch(SCHEMA)?;
        tx.pragma_update(None, "user_version", VERSION)?;
        tx.commit()?;
        crate::bookmarks::ensure_roots(self)?;
        crate::search::ensure_defaults(self)?;
        Ok(())
    }

    /// A stored preference, or `None`.
    pub fn pref(&self, key: &str) -> Result<Option<String>> {
        use rusqlite::OptionalExtension;
        Ok(self
            .conn
            .query_row("SELECT value FROM prefs WHERE key = ?1", [key], |r| {
                r.get(0)
            })
            .optional()?)
    }

    pub fn set_pref(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO prefs(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [key, value],
        )?;
        Ok(())
    }

    /// Checkpoints the WAL into the main file (on exit, after a clear).
    pub fn checkpoint(&self) -> Result<()> {
        if !self.is_ephemeral() {
            self.conn
                .execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_twice_and_keeps_prefs() {
        let d = tempfile::tempdir().unwrap();
        {
            let p = Profile::open(d.path()).unwrap();
            p.set_pref("a", "1").unwrap();
            p.set_pref("a", "2").unwrap();
        }
        let p = Profile::open(d.path()).unwrap();
        assert_eq!(p.pref("a").unwrap().as_deref(), Some("2"));
        assert_eq!(p.pref("b").unwrap(), None);
        let mode: String = p
            .conn
            .pragma_query_value(None, "journal_mode", |r| r.get(0))
            .unwrap();
        assert_eq!(mode, "wal");
    }

    #[test]
    fn memory_profile_is_ephemeral() {
        let p = Profile::in_memory().unwrap();
        assert!(p.is_ephemeral());
        assert!(p.path().is_none());
    }
}
