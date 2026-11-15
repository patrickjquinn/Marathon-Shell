// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The filter lists Pacific offers, their download state and their cached
//! text.
//!
//! The defaults (EasyList, EasyPrivacy, uBlock filters and privacy, Peter
//! Lowe's list) come with the package, so blocking works from the first
//! start and offline; the app refreshes them from their sources every
//! four days with conditional requests (ETag, Last-Modified). A download
//! that does not look like a filter list, or is larger than 30 MB, is
//! refused and the previous text kept.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::{hex, ListText};
use crate::util::write_atomic;
use crate::{Error, Result};

/// Refresh interval.
pub const UPDATE_EVERY_MS: i64 = 4 * 24 * 3600 * 1000;
/// Larger downloads are refused.
pub const MAX_LIST_BYTES: usize = 30 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FilterList {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub url: &'static str,
    pub default_on: bool,
    /// May use trusted scriptlets (uBlock Origin's own lists).
    pub trusted: bool,
}

/// The catalogue, in the order the settings page shows it.
pub const CATALOGUE: &[FilterList] = &[
    FilterList {
        id: "easylist",
        name: "EasyList",
        description: "Ads",
        url: "https://easylist.to/easylist/easylist.txt",
        default_on: true,
        trusted: false,
    },
    FilterList {
        id: "easyprivacy",
        name: "EasyPrivacy",
        description: "Trackers and analytics",
        url: "https://easylist.to/easylist/easyprivacy.txt",
        default_on: true,
        trusted: false,
    },
    FilterList {
        id: "ubo-filters",
        name: "uBlock filters",
        description: "Ads, pop-ups and anti-blocker scripts EasyList cannot express",
        url: "https://ublockorigin.github.io/uAssets/filters/filters.txt",
        default_on: true,
        trusted: true,
    },
    FilterList {
        id: "ubo-privacy",
        name: "uBlock filters: privacy",
        description: "Tracking parameters and more trackers",
        url: "https://ublockorigin.github.io/uAssets/filters/privacy.txt",
        default_on: true,
        trusted: true,
    },
    FilterList {
        id: "peter-lowe",
        name: "Peter Lowe's list",
        description: "Ad and tracking servers",
        url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext",
        default_on: true,
        trusted: false,
    },
    FilterList {
        id: "ubo-annoyances",
        name: "uBlock filters: annoyances",
        description: "Newsletter pop-ups, chat widgets, \"open in app\" banners",
        url: "https://ublockorigin.github.io/uAssets/filters/annoyances.txt",
        default_on: false,
        trusted: true,
    },
    FilterList {
        id: "fanboy-social",
        name: "Fanboy's social",
        description: "Social media buttons and widgets",
        url: "https://easylist.to/easylist/fanboy-social.txt",
        default_on: false,
        trusted: false,
    },
    FilterList {
        id: "easylist-cookie",
        name: "EasyList Cookie",
        description: "Hides cookie notices that cookie-banner rejection cannot answer",
        url: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt",
        default_on: false,
        trusted: false,
    },
];

pub fn by_id(id: &str) -> Option<&'static FilterList> {
    CATALOGUE.iter().find(|l| l.id == id)
}

/// Download state of one list (`lists.json`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListState {
    /// `None`: the list's default.
    pub enabled: Option<bool>,
    #[serde(default)]
    pub etag: String,
    #[serde(default)]
    pub last_modified: String,
    /// When the text was last fetched or confirmed unchanged (ms).
    #[serde(default)]
    pub checked_at: i64,
    #[serde(default)]
    pub sha256: String,
    #[serde(default)]
    pub size: usize,
    #[serde(default)]
    pub rules: usize,
    #[serde(default)]
    pub last_error: String,
}

/// One conditional request to make.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fetch {
    pub id: &'static str,
    pub url: &'static str,
    pub etag: String,
    pub last_modified: String,
}

/// The lists on disk: `<dir>/lists.json` and `<dir>/<id>.txt`, with the
/// packaged copies in `bundled` used until a download replaces them.
#[derive(Debug, Clone)]
pub struct ListStore {
    dir: PathBuf,
    bundled: Option<PathBuf>,
    state: BTreeMap<String, ListState>,
}

/// Whether `text` looks like an EasyList-format list (and not an error
/// page): a header or comment line first, or several rule-shaped lines.
pub fn looks_like_filter_list(text: &str) -> bool {
    let head = text.trim_start_matches('\u{feff}').trim_start();
    if head.starts_with("[Adblock") || head.starts_with('!') {
        return true;
    }
    let lower = head
        .get(..head.len().min(512))
        .unwrap_or("")
        .to_ascii_lowercase();
    if lower.contains("<html") || lower.contains("<!doctype") {
        return false;
    }
    head.lines()
        .take(20)
        .filter(|l| l.starts_with("||") || l.contains("##") || l.starts_with("@@"))
        .count()
        >= 3
}

/// Rule lines in a list (not comments or blank lines).
pub fn count_rules(text: &str) -> usize {
    text.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('!') && !l.starts_with('['))
        .count()
}

impl ListStore {
    pub fn open(dir: &Path, bundled: Option<&Path>) -> Self {
        let state = std::fs::read(dir.join("lists.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        Self {
            dir: dir.to_owned(),
            bundled: bundled.map(Path::to_owned),
            state,
        }
    }

    fn save(&self) -> Result<()> {
        write_atomic(
            &self.dir.join("lists.json"),
            &serde_json::to_vec_pretty(&self.state)?,
        )
    }

    pub fn state(&self, id: &str) -> ListState {
        self.state.get(id).cloned().unwrap_or_default()
    }

    pub fn is_enabled(&self, id: &str) -> bool {
        by_id(id).is_some_and(|l| self.state(id).enabled.unwrap_or(l.default_on))
    }

    pub fn set_enabled(&mut self, id: &str, on: bool) -> Result<()> {
        if by_id(id).is_none() {
            return Err(Error::NotFound(format!("filter list {id}")));
        }
        self.state.entry(id.to_owned()).or_default().enabled = Some(on);
        self.save()
    }

    /// The enabled lists' text (downloaded, else bundled); lists with no
    /// text yet are skipped.
    pub fn enabled_texts(&self) -> Vec<(&'static FilterList, String)> {
        CATALOGUE
            .iter()
            .filter(|l| self.is_enabled(l.id))
            .filter_map(|l| self.text(l.id).map(|t| (l, t)))
            .collect()
    }

    /// Builds the [`ListText`]s of [`Self::enabled_texts`].
    pub fn list_texts<'a>(texts: &'a [(&'static FilterList, String)]) -> Vec<ListText<'a>> {
        texts
            .iter()
            .map(|(l, t)| ListText {
                id: l.id,
                text: t,
                trusted: l.trusted,
            })
            .collect()
    }

    pub fn text(&self, id: &str) -> Option<String> {
        std::fs::read_to_string(self.dir.join(format!("{id}.txt")))
            .ok()
            .or_else(|| {
                let b = self.bundled.as_ref()?;
                std::fs::read_to_string(b.join(format!("{id}.txt"))).ok()
            })
    }

    /// The enabled lists due for a refresh at `now`.
    pub fn due(&self, now: i64, force: bool) -> Vec<Fetch> {
        CATALOGUE
            .iter()
            .filter(|l| self.is_enabled(l.id))
            .filter(|l| {
                let s = self.state(l.id);
                force || s.checked_at == 0 || now - s.checked_at >= UPDATE_EVERY_MS
            })
            .map(|l| {
                let s = self.state(l.id);
                Fetch {
                    id: l.id,
                    url: l.url,
                    etag: s.etag,
                    last_modified: s.last_modified,
                }
            })
            .collect()
    }

    /// Records a `304 Not Modified`.
    pub fn record_unchanged(&mut self, id: &str, now: i64) -> Result<()> {
        let s = self.state.entry(id.to_owned()).or_default();
        s.checked_at = now;
        s.last_error.clear();
        self.save()
    }

    /// Records a failed fetch; the old text stays.
    pub fn record_error(&mut self, id: &str, error: &str, now: i64) -> Result<()> {
        let s = self.state.entry(id.to_owned()).or_default();
        // Try again in an hour, not at once.
        s.checked_at = now - UPDATE_EVERY_MS + 3600 * 1000;
        s.last_error = crate::util::truncate_chars(error, 200);
        self.save()
    }

    /// Stores a downloaded list. Returns whether the text changed (the
    /// engine then needs rebuilding).
    pub fn store(
        &mut self,
        id: &str,
        body: &[u8],
        etag: &str,
        last_modified: &str,
        now: i64,
    ) -> Result<bool> {
        if by_id(id).is_none() {
            return Err(Error::NotFound(format!("filter list {id}")));
        }
        if body.len() > MAX_LIST_BYTES {
            return Err(Error::Blocker(format!("{id}: the list is too large")));
        }
        let text = std::str::from_utf8(body)
            .map_err(|_| Error::Blocker(format!("{id}: not UTF-8 text")))?;
        if !looks_like_filter_list(text) {
            return Err(Error::Blocker(format!(
                "{id}: the download is not a filter list"
            )));
        }
        let sha = hex(&Sha256::digest(body));
        let changed = self.state(id).sha256 != sha;
        if changed {
            write_atomic(&self.dir.join(format!("{id}.txt")), body)?;
        }
        let s = self.state.entry(id.to_owned()).or_default();
        etag.clone_into(&mut s.etag);
        last_modified.clone_into(&mut s.last_modified);
        s.checked_at = now;
        s.sha256 = sha;
        s.size = body.len();
        s.rules = count_rules(text);
        s.last_error.clear();
        self.save()?;
        Ok(changed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOD: &str = "[Adblock Plus 2.0]\n! Title: test\n||ads.example^\n##.ad\n";

    #[test]
    fn defaults_and_toggles() {
        let d = tempfile::tempdir().unwrap();
        let mut s = ListStore::open(d.path(), None);
        assert!(s.is_enabled("easylist"));
        assert!(!s.is_enabled("ubo-annoyances"));
        assert!(!s.is_enabled("nope"));
        s.set_enabled("ubo-annoyances", true).unwrap();
        s.set_enabled("easylist", false).unwrap();
        let s = ListStore::open(d.path(), None);
        assert!(s.is_enabled("ubo-annoyances"));
        assert!(!s.is_enabled("easylist"));
        assert!(ListStore::open(d.path(), None)
            .clone()
            .set_enabled("nope", true)
            .is_err());
    }

    #[test]
    fn stores_validates_and_schedules() {
        let d = tempfile::tempdir().unwrap();
        let mut s = ListStore::open(d.path(), None);
        let now = 1_000_000_000_000;
        let due: Vec<_> = s.due(now, false).into_iter().map(|f| f.id).collect();
        assert_eq!(
            due,
            [
                "easylist",
                "easyprivacy",
                "ubo-filters",
                "ubo-privacy",
                "peter-lowe"
            ]
        );
        assert!(s
            .store("easylist", GOOD.as_bytes(), "\"e1\"", "", now)
            .unwrap());
        assert!(!s
            .store("easylist", GOOD.as_bytes(), "\"e1\"", "", now)
            .unwrap());
        assert_eq!(s.state("easylist").rules, 2);
        assert!(s
            .store(
                "easylist",
                b"<!DOCTYPE html><html>error</html>",
                "",
                "",
                now
            )
            .is_err());
        assert_eq!(s.text("easylist").unwrap(), GOOD);
        let due = s.due(now + 1000, false);
        assert!(!due.iter().any(|f| f.id == "easylist"));
        let later = s.due(now + UPDATE_EVERY_MS, false);
        let e = later.iter().find(|f| f.id == "easylist").unwrap();
        assert_eq!(e.etag, "\"e1\"");
        s.record_error("easyprivacy", "timeout", now).unwrap();
        assert!(!s
            .due(now + 1000, false)
            .iter()
            .any(|f| f.id == "easyprivacy"));
        assert!(s
            .due(now + 3600 * 1000, false)
            .iter()
            .any(|f| f.id == "easyprivacy"));
        s.record_unchanged("easyprivacy", now).unwrap();
        assert_eq!(s.state("easyprivacy").last_error, "");
        assert_eq!(s.due(now, true).len(), 5);
    }

    #[test]
    fn bundled_text_until_downloaded() {
        let d = tempfile::tempdir().unwrap();
        let b = tempfile::tempdir().unwrap();
        std::fs::write(b.path().join("easylist.txt"), "! bundled\n||a.example^\n").unwrap();
        let mut s = ListStore::open(d.path(), Some(b.path()));
        assert_eq!(s.enabled_texts().len(), 1);
        assert!(s.text("easylist").unwrap().contains("bundled"));
        s.store("easylist", GOOD.as_bytes(), "", "", 1).unwrap();
        assert_eq!(s.text("easylist").unwrap(), GOOD);
        let texts = s.enabled_texts();
        let lt = ListStore::list_texts(&texts);
        assert_eq!(lt[0].id, "easylist");
        assert!(!lt[0].trusted);
    }

    #[test]
    fn list_detection() {
        assert!(looks_like_filter_list(GOOD));
        assert!(looks_like_filter_list("\u{feff}! comment"));
        assert!(looks_like_filter_list("||a^\n||b^\nx##.y\n"));
        assert!(!looks_like_filter_list("<html><body>404</body></html>"));
        assert!(!looks_like_filter_list("hello"));
    }
}
