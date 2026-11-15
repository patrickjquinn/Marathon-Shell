// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The session: open tabs with their back/forward stacks and scroll
//! positions, and recently closed tabs, so the browser comes back as it
//! was after a restart, an update or a crash.
//!
//! Stored as `session.lz4` (LZ4-compressed JSON, magic `PSS1`), written
//! atomically; the previous good file is kept as `session.bak.lz4` and used
//! if the current one is damaged. Private tabs are never written.
//!
//! Crash detection: [`SessionStore::mark_running`] creates a `running`
//! marker at start-up and [`SessionStore::mark_clean_exit`] removes it on a
//! normal exit. A marker found at start-up means the last run did not end
//! cleanly; the UI then restores the tabs and says so.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::util::write_atomic;
use crate::{Error, Result};

const MAGIC: &[u8; 4] = b"PSS1";
/// Larger sessions are refused when reading (a damaged length).
const MAX_SESSION: usize = 64 * 1024 * 1024;
/// Recently closed tabs kept for "reopen closed tab".
pub const MAX_CLOSED: usize = 10;
/// Back/forward entries kept per tab.
pub const MAX_ENTRIES: usize = 50;

/// One entry of a tab's back/forward list.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct HistoryEntry {
    pub url: String,
    #[serde(default)]
    pub title: String,
    /// Vertical scroll position in CSS pixels.
    #[serde(default)]
    pub scroll_y: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct TabState {
    pub id: i64,
    pub entries: Vec<HistoryEntry>,
    /// The current entry.
    pub index: usize,
    #[serde(default)]
    pub pinned: bool,
    /// Milliseconds since the epoch.
    #[serde(default)]
    pub last_active: i64,
    /// The engine's own serialised session state (WebKit's
    /// `webkit_web_view_get_session_state`), base64, when the view offers
    /// it; restores form data and the exact back/forward list.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub engine_state: String,
    /// Path of the tab's last thumbnail, if any.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub thumbnail: String,
}

impl TabState {
    /// The current entry, if any.
    pub fn current(&self) -> Option<&HistoryEntry> {
        self.entries.get(self.index)
    }

    /// Bounds the entries (oldest dropped first) and the index.
    pub fn normalise(&mut self) {
        if self.entries.len() > MAX_ENTRIES {
            let drop = self.entries.len() - MAX_ENTRIES;
            self.entries.drain(..drop);
            self.index = self.index.saturating_sub(drop);
        }
        if self.index >= self.entries.len() {
            self.index = self.entries.len().saturating_sub(1);
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClosedTab {
    pub tab: TabState,
    /// Where it was in the tab strip.
    pub position: usize,
    pub closed_at: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Session {
    pub tabs: Vec<TabState>,
    /// Index into `tabs` of the tab in front.
    pub active: usize,
    #[serde(default)]
    pub closed: Vec<ClosedTab>,
    /// Next tab id to hand out (ids are never reused within a profile).
    #[serde(default)]
    pub next_id: i64,
}

impl Session {
    /// Remembers a closed tab (newest first), bounded to [`MAX_CLOSED`].
    pub fn push_closed(&mut self, tab: TabState, position: usize, closed_at: i64) {
        if tab.entries.is_empty() {
            return;
        }
        self.closed.insert(
            0,
            ClosedTab {
                tab,
                position,
                closed_at,
            },
        );
        self.closed.truncate(MAX_CLOSED);
    }

    /// Takes the most recently closed tab back out.
    pub fn pop_closed(&mut self) -> Option<ClosedTab> {
        (!self.closed.is_empty()).then(|| self.closed.remove(0))
    }

    /// Makes the session consistent before saving or after loading.
    pub fn normalise(&mut self) {
        self.tabs.retain(|t| !t.entries.is_empty());
        for t in &mut self.tabs {
            t.normalise();
        }
        if self.active >= self.tabs.len() {
            self.active = self.tabs.len().saturating_sub(1);
        }
        let max = self
            .tabs
            .iter()
            .map(|t| t.id)
            .chain(self.closed.iter().map(|c| c.tab.id))
            .max()
            .unwrap_or(0);
        self.next_id = self.next_id.max(max + 1);
        self.closed.truncate(MAX_CLOSED);
    }

    pub fn encode(&self) -> Result<Vec<u8>> {
        let json = serde_json::to_vec(self)?;
        let mut out = MAGIC.to_vec();
        out.extend_from_slice(&lz4_flex::compress_prepend_size(&json));
        Ok(out)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self> {
        let body = bytes
            .strip_prefix(MAGIC.as_slice())
            .ok_or_else(|| Error::Session("not a Pacific session file".into()))?;
        if body.len() < 4 {
            return Err(Error::Session("truncated".into()));
        }
        let declared = u32::from_le_bytes([body[0], body[1], body[2], body[3]]) as usize;
        if declared > MAX_SESSION {
            return Err(Error::Session("too large".into()));
        }
        let json =
            lz4_flex::decompress_size_prepended(body).map_err(|e| Error::Session(e.to_string()))?;
        let mut s: Self = serde_json::from_slice(&json)?;
        s.normalise();
        Ok(s)
    }
}

/// What [`SessionStore::load`] found.
#[derive(Debug, Default)]
pub struct Loaded {
    pub session: Session,
    /// The last run did not exit cleanly.
    pub crashed: bool,
    /// The main file was damaged and the backup was used (or nothing).
    pub recovered_from_backup: bool,
}

#[derive(Debug, Clone)]
pub struct SessionStore {
    dir: PathBuf,
}

impl SessionStore {
    pub fn new(dir: &Path) -> Self {
        Self {
            dir: dir.to_owned(),
        }
    }

    fn main(&self) -> PathBuf {
        self.dir.join("session.lz4")
    }

    fn backup(&self) -> PathBuf {
        self.dir.join("session.bak.lz4")
    }

    fn marker(&self) -> PathBuf {
        self.dir.join("running")
    }

    /// Reads the saved session (an empty one when there is none).
    pub fn load(&self) -> Loaded {
        let crashed = self.marker().exists();
        let read = |p: PathBuf| std::fs::read(p).ok().and_then(|b| Session::decode(&b).ok());
        if let Some(session) = read(self.main()) {
            return Loaded {
                session,
                crashed,
                recovered_from_backup: false,
            };
        }
        Loaded {
            session: read(self.backup()).unwrap_or_default(),
            crashed,
            recovered_from_backup: self.main().exists(),
        }
    }

    /// Saves `session` atomically, keeping the previous file as backup.
    pub fn save(&self, session: &Session) -> Result<()> {
        let mut s = session.clone();
        s.normalise();
        let bytes = s.encode()?;
        if self.main().exists() {
            let _ = std::fs::rename(self.main(), self.backup());
        }
        write_atomic(&self.main(), &bytes)
    }

    pub fn mark_running(&self) -> Result<()> {
        write_atomic(&self.marker(), b"1")
    }

    pub fn mark_clean_exit(&self) -> Result<()> {
        match std::fs::remove_file(self.marker()) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(Error::io(self.marker(), e)),
        }
    }

    /// Deletes the session files (clearing data).
    pub fn clear(&self) -> Result<()> {
        for p in [self.main(), self.backup()] {
            if let Err(e) = std::fs::remove_file(&p) {
                if e.kind() != std::io::ErrorKind::NotFound {
                    return Err(Error::io(p, e));
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tab(id: i64, urls: &[&str], index: usize) -> TabState {
        TabState {
            id,
            entries: urls
                .iter()
                .map(|u| HistoryEntry {
                    url: (*u).into(),
                    title: format!("T {u}"),
                    scroll_y: 120.5,
                })
                .collect(),
            index,
            ..TabState::default()
        }
    }

    #[test]
    fn round_trip_with_scroll_and_history() {
        let d = tempfile::tempdir().unwrap();
        let store = SessionStore::new(d.path());
        let mut s = Session {
            tabs: vec![
                tab(1, &["https://a/", "https://b/"], 1),
                tab(4, &["https://c/"], 0),
            ],
            active: 1,
            ..Session::default()
        };
        s.push_closed(tab(3, &["https://closed/"], 0), 1, 99);
        store.save(&s).unwrap();
        let loaded = store.load();
        assert!(!loaded.crashed);
        assert_eq!(loaded.session.tabs, s.tabs);
        assert_eq!(loaded.session.active, 1);
        assert_eq!(loaded.session.next_id, 5);
        assert_eq!(loaded.session.tabs[0].current().unwrap().url, "https://b/");
        assert!((loaded.session.tabs[0].entries[0].scroll_y - 120.5).abs() < f64::EPSILON);
        assert_eq!(loaded.session.closed.len(), 1);
    }

    #[test]
    fn crash_marker() {
        let d = tempfile::tempdir().unwrap();
        let store = SessionStore::new(d.path());
        store.mark_running().unwrap();
        assert!(store.load().crashed);
        store.mark_clean_exit().unwrap();
        store.mark_clean_exit().unwrap();
        assert!(!store.load().crashed);
    }

    #[test]
    fn damaged_file_falls_back_to_backup() {
        let d = tempfile::tempdir().unwrap();
        let store = SessionStore::new(d.path());
        let one = Session {
            tabs: vec![tab(1, &["https://one/"], 0)],
            ..Session::default()
        };
        let two = Session {
            tabs: vec![tab(2, &["https://two/"], 0)],
            ..Session::default()
        };
        store.save(&one).unwrap();
        store.save(&two).unwrap();
        std::fs::write(d.path().join("session.lz4"), b"PSS1garbage").unwrap();
        let loaded = store.load();
        assert!(loaded.recovered_from_backup);
        assert_eq!(loaded.session.tabs[0].entries[0].url, "https://one/");
        store.clear().unwrap();
        assert!(store.load().session.tabs.is_empty());
    }

    #[test]
    fn normalises_bounds() {
        let mut t = tab(1, &[], 0);
        t.entries = (0..60)
            .map(|i| HistoryEntry {
                url: format!("https://e/{i}"),
                ..HistoryEntry::default()
            })
            .collect();
        t.index = 55;
        let mut s = Session {
            tabs: vec![t, tab(2, &[], 0)],
            active: 9,
            ..Session::default()
        };
        for i in 0..15 {
            s.push_closed(tab(10 + i, &["https://x/"], 0), 0, i);
        }
        s.normalise();
        assert_eq!(s.tabs.len(), 1);
        assert_eq!(s.tabs[0].entries.len(), MAX_ENTRIES);
        assert_eq!(s.tabs[0].index, 45);
        assert_eq!(s.tabs[0].current().unwrap().url, "https://e/55");
        assert_eq!(s.active, 0);
        assert_eq!(s.closed.len(), MAX_CLOSED);
        assert_eq!(s.pop_closed().unwrap().tab.id, 24);
    }

    #[test]
    fn rejects_foreign_and_huge_files() {
        assert!(Session::decode(b"nope").is_err());
        let mut b = MAGIC.to_vec();
        b.extend_from_slice(&u32::MAX.to_le_bytes());
        assert!(Session::decode(&b).is_err());
    }
}
