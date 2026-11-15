// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Which content filters the engine holds, recorded only once the engine's
//! store has confirmed them.
//!
//! Converting the lists to WebKit content-blocker JSON is slow, and the
//! engine compiles that JSON once into its own store. A run can be killed
//! between the two (on the first start the compile takes seconds), so the
//! record keeps, per set of lists (`key`), the filter ids wanted, each
//! filter's JSON on disk (to compile it again without converting again)
//! and the ids the engine confirmed. At every start [`FilterRecord::pending`]
//! names the filters to compile again: those never confirmed, and those the
//! engine could not load from its store.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::util::write_atomic;
use crate::Result;

use super::webkit::ContentFilter;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
struct Record {
    key: String,
    ids: Vec<String>,
    confirmed: Vec<String>,
}

/// The record in `<dir>/filters.json`, the JSON in `<dir>/content-filters/`.
pub struct FilterRecord {
    dir: PathBuf,
    record: Record,
}

impl FilterRecord {
    pub fn open(dir: &Path) -> Self {
        let record = std::fs::read(dir.join("filters.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        Self {
            dir: dir.to_owned(),
            record,
        }
    }

    fn json_path(&self, id: &str) -> PathBuf {
        // Ids are ours ("pacific-<list>-<n>"); anything else is refused.
        self.dir.join("content-filters").join(format!("{id}.json"))
    }

    fn valid_id(id: &str) -> bool {
        !id.is_empty()
            && id.len() <= 128
            && id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    }

    /// Whether the record is for this set of lists and every filter's JSON
    /// is still on disk.
    pub fn is_current(&self, key: &str) -> bool {
        self.record.key == key
            && self
                .record
                .ids
                .iter()
                .all(|id| self.json_path(id).is_file())
    }

    /// The filters wanted (for the engine to load or compile).
    pub fn ids(&self) -> &[String] {
        &self.record.ids
    }

    /// Starts a new set: writes every filter's JSON, then the record with
    /// nothing confirmed yet. A kill at any point leaves a record that
    /// either names the old set or names this one with nothing confirmed.
    pub fn replace(&mut self, key: &str, filters: &[ContentFilter]) -> Result<()> {
        let json_dir = self.dir.join("content-filters");
        std::fs::create_dir_all(&json_dir).map_err(|e| crate::Error::io(&json_dir, e))?;
        for f in filters {
            if Self::valid_id(&f.identifier) {
                write_atomic(&self.json_path(&f.identifier), f.json.as_bytes())?;
            }
        }
        // JSON of filters no longer wanted goes.
        let keep: Vec<&str> = filters.iter().map(|f| f.identifier.as_str()).collect();
        if let Ok(entries) = std::fs::read_dir(&json_dir) {
            for e in entries.flatten() {
                let name = e.file_name().to_string_lossy().into_owned();
                if let Some(id) = name.strip_suffix(".json") {
                    if !keep.contains(&id) {
                        let _ = std::fs::remove_file(e.path());
                    }
                }
            }
        }
        self.record = Record {
            key: key.to_owned(),
            ids: keep.iter().map(|s| (*s).to_owned()).collect(),
            confirmed: Vec::new(),
        };
        self.save()
    }

    fn save(&self) -> Result<()> {
        write_atomic(
            &self.dir.join("filters.json"),
            &serde_json::to_vec(&self.record)?,
        )
    }

    /// The filters to compile again: wanted and not confirmed.
    pub fn pending(&self) -> Vec<String> {
        self.record
            .ids
            .iter()
            .filter(|id| !self.record.confirmed.contains(id))
            .cloned()
            .collect()
    }

    /// The JSON to compile a filter from.
    pub fn json(&self, id: &str) -> Option<String> {
        if !Self::valid_id(id) || !self.record.ids.iter().any(|i| i == id) {
            return None;
        }
        std::fs::read_to_string(self.json_path(id)).ok()
    }

    /// The engine's answer for a filter: compiled (or loaded) and in its
    /// store, or not (it is compiled again at the next chance).
    pub fn confirm(&mut self, id: &str, ok: bool) -> Result<()> {
        if !self.record.ids.iter().any(|i| i == id) {
            return Ok(());
        }
        let had = self.record.confirmed.iter().any(|i| i == id);
        if ok && !had {
            self.record.confirmed.push(id.to_owned());
        } else if !ok && had {
            self.record.confirmed.retain(|i| i != id);
        } else {
            return Ok(());
        }
        self.save()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn filters(n: usize) -> Vec<ContentFilter> {
        (0..n)
            .map(|i| ContentFilter {
                identifier: format!("pacific-easylist-{i}"),
                json: format!("[{{\"n\":{i}}}]"),
                rules: 1,
            })
            .collect()
    }

    #[test]
    fn a_run_killed_during_the_compile_compiles_again() {
        let d = tempfile::tempdir().unwrap();
        // First start: converted and recorded, then killed while the engine
        // compiled (nothing confirmed).
        let mut r = FilterRecord::open(d.path());
        assert!(!r.is_current("k1"));
        r.replace("k1", &filters(2)).unwrap();
        drop(r);
        // Next start: the same lists, so no conversion, but both filters
        // are compiled again from the JSON kept on disk.
        let mut r = FilterRecord::open(d.path());
        assert!(r.is_current("k1"));
        assert_eq!(r.pending(), ["pacific-easylist-0", "pacific-easylist-1"]);
        assert_eq!(r.json("pacific-easylist-1").unwrap(), "[{\"n\":1}]");
        // One confirmed, then killed again.
        r.confirm("pacific-easylist-0", true).unwrap();
        drop(r);
        let mut r = FilterRecord::open(d.path());
        assert_eq!(r.pending(), ["pacific-easylist-1"]);
        r.confirm("pacific-easylist-1", true).unwrap();
        assert!(FilterRecord::open(d.path()).pending().is_empty());
        // The engine later fails to load one from its store: compiled again.
        r.confirm("pacific-easylist-0", false).unwrap();
        assert_eq!(
            FilterRecord::open(d.path()).pending(),
            ["pacific-easylist-0"]
        );
    }

    #[test]
    fn new_lists_replace_the_set_and_its_json() {
        let d = tempfile::tempdir().unwrap();
        let mut r = FilterRecord::open(d.path());
        r.replace("k1", &filters(3)).unwrap();
        r.confirm("pacific-easylist-0", true).unwrap();
        r.replace("k2", &filters(1)).unwrap();
        assert_eq!(r.ids(), ["pacific-easylist-0"]);
        assert_eq!(
            r.pending(),
            ["pacific-easylist-0"],
            "a new set starts unconfirmed"
        );
        assert!(r.json("pacific-easylist-2").is_none());
        assert!(!d
            .path()
            .join("content-filters/pacific-easylist-2.json")
            .exists());
        // JSON lost from disk: the record is not current (convert again).
        std::fs::remove_file(d.path().join("content-filters/pacific-easylist-0.json")).unwrap();
        assert!(!FilterRecord::open(d.path()).is_current("k2"));
        // Ids from outside are refused.
        assert!(r.json("../filters").is_none());
        r.confirm("unknown", true).unwrap();
        assert_eq!(r.pending(), ["pacific-easylist-0"]);
    }
}
