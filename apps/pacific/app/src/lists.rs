// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! `PacificList`: the browser's lists as one QML list model type, chosen
//! by `kind`:
//!
//! | kind | rows | filters |
//! | --- | --- | --- |
//! | `history` | pages, newest first, with a `section` (local date) | `query` |
//! | `bookmarks` | a folder's children, or matches of `query` | `folder`, `query` |
//! | `folders` | every folder with its `depth` | |
//! | `topSites` | the most frecent pages, one per site | `limit` |
//! | `recentBookmarks` | newest bookmarks | `limit` |
//! | `downloads` | newest first | |
//! | `engines` | search engines | |
//! | `filterLists` | the filter-list catalogue with state | |
//! | `sites` | sites with their own settings | |
//! | `httpsExceptions` | hosts loaded over HTTP | |
//!
//! Rows are read on the core thread whenever a filter changes or
//! `revision` is set (bind it to `Pacific.revision`).

pub use crate::models::qobject;

use core::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use pacific_core::blocker::lists::CATALOGUE;
use serde_json::{json, Map, Value};

use crate::worker::{self, Core};

/// Every role a row can have; a row leaves out what its kind lacks.
const ROLES: &[&str] = &[
    "itemId", "title", "url", "host", "subtitle", "icon", "isFolder", "section", "time", "status",
    "progress", "path", "on", "depth", "detail", "builtin", "keyword",
];

type Row = Map<String, Value>;

pub struct PacificListRust {
    pub(crate) kind: QString,
    pub(crate) query: QString,
    pub(crate) folder: i32,
    pub(crate) limit: i32,
    pub(crate) revision: i32,
    pub(crate) count: i32,
    pub(crate) loading: bool,
    pub(crate) rows: Vec<Row>,
    pub(crate) generation: u64,
}

impl Default for PacificListRust {
    fn default() -> Self {
        Self {
            kind: QString::default(),
            query: QString::default(),
            folder: 1,
            limit: 0,
            revision: 0,
            count: 0,
            loading: true,
            rows: Vec::new(),
            generation: 0,
        }
    }
}

fn obj(v: Value) -> Row {
    match v {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

/// The rows of `kind`, read on the core thread.
#[allow(clippy::too_many_lines, reason = "one arm per list kind")]
pub fn read_rows(c: &Core, kind: &str, query: &str, folder: i64, limit: usize) -> Vec<Row> {
    let p = &c.profile;
    let limit = if limit == 0 { 500 } else { limit };
    let offset = crate::time::local_utc_offset();
    let r: Result<Vec<Row>, pacific_core::Error> = (|| {
        Ok(match kind {
            "history" => p
                .history(query, 0, limit, 0)?
                .into_iter()
                .map(|h| {
                    obj(json!({
                        "itemId": h.id, "title": if h.title.is_empty() { h.url.clone() } else { h.title.clone() },
                        "url": h.url, "host": h.host, "icon": c.dirs.favicon_url(&h.icon_url), "time": h.last_visit,
                        "section": crate::time::local_date(h.last_visit, offset),
                        "subtitle": h.host,
                    }))
                })
                .collect(),
            "bookmarks" => {
                let list = if query.trim().is_empty() { p.bookmarks_in(folder)? } else { p.find_bookmarks(query, limit)? };
                list.into_iter()
                    .map(|b| {
                        let host = pacific_core::util::display_host(&b.url);
                        obj(json!({
                            "itemId": b.id, "title": b.title, "url": b.url, "isFolder": b.folder,
                            "host": host, "subtitle": if b.folder { String::new() } else { host.clone() },
                            "time": b.added, "detail": b.parent,
                        }))
                    })
                    .collect()
            }
            "folders" => p
                .folder_tree()?
                .into_iter()
                .map(|(b, depth)| obj(json!({ "itemId": b.id, "title": b.title, "depth": depth, "isFolder": true })))
                .collect(),
            "topSites" => p
                .top_sites(limit.min(24))?
                .into_iter()
                .map(|t| {
                    obj(json!({
                        "itemId": t.id, "title": if t.title.is_empty() { t.host.clone() } else { t.title.clone() },
                        "url": t.url, "host": t.host, "icon": c.dirs.favicon_url(&t.icon_url),
                    }))
                })
                .collect(),
            "recentBookmarks" => p
                .recent_bookmarks(limit.min(50))?
                .into_iter()
                .map(|b| {
                    let host = pacific_core::util::display_host(&b.url);
                    let icon = p.place(&b.url).ok().flatten().map(|pl| c.dirs.favicon_url(&pl.icon_url)).unwrap_or_default();
                    obj(json!({ "itemId": b.id, "title": b.title, "url": b.url, "host": host, "subtitle": host, "icon": icon }))
                })
                .collect(),
            "downloads" => p
                .downloads()?
                .into_iter()
                .map(|d| {
                    obj(json!({
                        "itemId": d.id, "title": d.file_name, "url": d.url, "path": d.path,
                        "status": d.state, "progress": d.progress(), "time": d.started,
                        "subtitle": pacific_core::util::display_host(&d.url), "detail": d.error,
                        "host": d.mime,
                    }))
                })
                .collect(),
            "engines" => {
                let def = p.default_engine()?.id;
                p.search_engines()?
                    .into_iter()
                    .map(|e| {
                        obj(json!({
                            "itemId": e.id, "title": e.name, "keyword": e.keyword, "url": e.search_url,
                            "builtin": e.builtin, "on": e.id == def,
                            "subtitle": pacific_core::util::display_host(&e.search_url.replace("{searchTerms}", "x")),
                        }))
                    })
                    .collect()
            }
            "filterLists" => CATALOGUE
                .iter()
                .map(|l| {
                    let s = c.lists.state(l.id);
                    obj(json!({
                        "itemId": l.id, "title": l.name, "subtitle": l.description, "url": l.url,
                        "on": c.lists.is_enabled(l.id), "time": s.checked_at,
                        "detail": s.last_error, "progress": s.rules,
                    }))
                })
                .collect(),
            "sites" => p
                .sites_with_settings()?
                .into_iter()
                .map(|s| {
                    let mut parts = Vec::new();
                    if let Some(z) = s.zoom {
                        parts.push(format!("{}%", (z * 100.0).round()));
                    }
                    if s.desktop == Some(true) {
                        parts.push("desktop".into());
                    }
                    if s.javascript == Some(false) {
                        parts.push("no JavaScript".into());
                    }
                    if s.blocking == Some(false) {
                        parts.push("blocking off".into());
                    }
                    for (perm, a) in &s.permissions {
                        parts.push(format!("{perm}: {}", serde_json::to_string(a).unwrap_or_default().trim_matches('"')));
                    }
                    obj(json!({ "itemId": s.site, "title": s.site, "host": s.site, "subtitle": parts.join(", "), "detail": serde_json::to_string(&s).unwrap_or_default() }))
                })
                .collect(),
            "httpsExceptions" => p
                .https_exceptions()?
                .into_iter()
                .map(|h| obj(json!({ "itemId": h, "title": h, "host": h })))
                .collect(),
            _ => Vec::new(),
        })
    })();
    r.unwrap_or_else(|e| {
        log::warn!("list {kind}: {e}");
        Vec::new()
    })
}

fn variant(v: &Value) -> QVariant {
    match v {
        Value::Bool(b) => QVariant::from(b),
        Value::Number(n) => {
            if let Some(i) = n.as_i64().and_then(|i| i32::try_from(i).ok()) {
                QVariant::from(&i)
            } else {
                QVariant::from(&n.as_f64().unwrap_or(0.0))
            }
        }
        Value::String(s) => QVariant::from(&QString::from(s.as_str())),
        Value::Null => QVariant::default(),
        other => QVariant::from(&QString::from(other.to_string().as_str())),
    }
}

impl qobject::PacificList {
    pub(crate) fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(row) = usize::try_from(index.row())
            .ok()
            .and_then(|r| self.rows.get(r))
        else {
            return QVariant::default();
        };
        let Some(name) = usize::try_from(role).ok().and_then(|r| ROLES.get(r)) else {
            return QVariant::default();
        };
        row.get(*name).map_or_else(QVariant::default, variant)
    }

    pub(crate) fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            i32::try_from(self.rows.len()).unwrap_or(i32::MAX)
        }
    }

    #[allow(clippy::unused_self)]
    pub(crate) fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (i, name) in ROLES.iter().enumerate() {
            roles.insert(i32::try_from(i).unwrap_or(0), QByteArray::from(*name));
        }
        roles
    }

    pub(crate) fn get(&self, index: i32) -> QString {
        let row = usize::try_from(index).ok().and_then(|r| self.rows.get(r));
        QString::from(
            row.map_or_else(|| "{}".into(), |r| Value::Object(r.clone()).to_string())
                .as_str(),
        )
    }

    pub(crate) fn set_kind(mut self: Pin<&mut Self>, kind: QString) {
        if self.kind != kind {
            self.as_mut().rust_mut().kind = kind;
            self.as_mut().kind_changed();
            self.refresh();
        }
    }

    pub(crate) fn set_query(mut self: Pin<&mut Self>, query: QString) {
        if self.query != query {
            self.as_mut().rust_mut().query = query;
            self.as_mut().query_changed();
            self.refresh();
        }
    }

    pub(crate) fn set_folder(mut self: Pin<&mut Self>, folder: i32) {
        if self.folder != folder {
            self.as_mut().rust_mut().folder = folder;
            self.as_mut().folder_changed();
            self.refresh();
        }
    }

    pub(crate) fn set_limit(mut self: Pin<&mut Self>, limit: i32) {
        if self.limit != limit {
            self.as_mut().rust_mut().limit = limit;
            self.as_mut().limit_changed();
            self.refresh();
        }
    }

    pub(crate) fn set_revision(mut self: Pin<&mut Self>, revision: i32) {
        if self.revision != revision {
            self.as_mut().rust_mut().revision = revision;
            self.as_mut().revision_changed();
            self.refresh();
        }
    }

    pub(crate) fn refresh(mut self: Pin<&mut Self>) {
        let kind = self.kind.to_string();
        if kind.is_empty() {
            return;
        }
        let generation = self.generation.wrapping_add(1);
        self.as_mut().rust_mut().generation = generation;
        let query = self.query.to_string();
        let folder = i64::from(self.folder);
        let limit = usize::try_from(self.limit).unwrap_or(0);
        let thread = self.qt_thread();
        worker::run(move |c| {
            let rows = read_rows(c, &kind, &query, folder, limit);
            let _ = thread.queue(move |q| q.show(generation, rows));
        });
    }

    pub(crate) fn show(mut self: Pin<&mut Self>, generation: u64, rows: Vec<Row>) {
        if generation != self.generation {
            return;
        }
        self.as_mut().begin_reset_model();
        self.as_mut().rust_mut().rows = rows;
        self.as_mut().end_reset_model();
        let count = i32::try_from(self.rows.len()).unwrap_or(0);
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }
        if self.loading {
            self.as_mut().rust_mut().loading = false;
            self.as_mut().loading_changed();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pacific_core::frecency::Transition;

    fn core() -> (tempfile::TempDir, Core) {
        let d = tempfile::tempdir().unwrap();
        let dirs = worker::Dirs {
            data: d.path().join("data"),
            cache: d.path().join("cache"),
            downloads: d.path().join("dl"),
            share: d.path().join("share"),
        };
        let c = worker::open_core_for_tests(dirs);
        (d, c)
    }

    #[test]
    fn every_kind_reads() {
        let (_d, c) = core();
        c.profile
            .record_visit("https://a.example/", Some("A"), Transition::Typed, 1_000)
            .unwrap();
        c.profile
            .add_bookmark("https://b.example/", "B", 1)
            .unwrap();
        c.profile
            .set_site_setting("a.example", "zoom", "1.5")
            .unwrap();
        let n = |k: &str| read_rows(&c, k, "", 1, 0).len();
        assert_eq!(n("history"), 1);
        assert_eq!(n("bookmarks"), 1);
        assert_eq!(n("folders"), 1);
        assert_eq!(n("topSites"), 1);
        assert_eq!(n("recentBookmarks"), 1);
        assert_eq!(n("downloads"), 0);
        assert!(n("engines") >= 9);
        assert_eq!(n("filterLists"), CATALOGUE.len());
        assert_eq!(n("sites"), 1);
        assert_eq!(n("httpsExceptions"), 0);
        assert_eq!(n("nonsense"), 0);
        let h = &read_rows(&c, "history", "", 1, 0)[0];
        assert!(h["section"].as_str().unwrap().starts_with("19"));
        let s = &read_rows(&c, "sites", "", 1, 0)[0];
        assert_eq!(s["subtitle"], "150%");
        assert_eq!(read_rows(&c, "engines", "", 1, 0)[0]["on"], true);
    }
}
