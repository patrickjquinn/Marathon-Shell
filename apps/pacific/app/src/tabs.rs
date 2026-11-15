// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `TabModel`: the open tabs of one kind (normal or private) as a QML list
//! model. The UI creates one of each; a `Repeater` over each creates the
//! web views, and the tab grid shows the same rows.
//!
//! Rows change in place (`dataChanged` with the changed roles), never by a
//! reset, so a title or progress update never recreates a web view. Tab
//! ids are unique across both models for the life of the profile.
//!
//! The normal model is the session: [`qobject::TabModel::session_json`]
//! is what `Pacific.saveSession` writes, and `restore` brings it back with
//! every tab unloaded (`live: false`) until it is shown. Private tabs are
//! never saved.

pub use crate::models::qobject;

use core::pin::Pin;
use std::sync::atomic::{AtomicI32, Ordering};

use cxx_qt::CxxQtType;
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QModelIndex, QString, QVariant,
};
use pacific_core::session::{ClosedTab, HistoryEntry, Session, TabState};
use pacific_core::util::now_ms;
use serde::Deserialize;
use serde_json::json;

/// The next tab id, shared by both models.
static NEXT_ID: AtomicI32 = AtomicI32::new(1);

fn next_id() -> i32 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

#[derive(Debug, Clone, Default, PartialEq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent facts about a tab"
)]
pub struct Tab {
    pub id: i32,
    pub url: String,
    pub title: String,
    pub icon: String,
    pub thumbnail: String,
    pub loading: bool,
    pub progress: i32,
    pub pinned: bool,
    pub audible: bool,
    pub live: bool,
    pub form_dirty: bool,
    pub desktop: bool,
    pub last_active: i64,
    pub engine_state: String,
    pub scroll_y: f64,
    pub history: Vec<HistoryEntry>,
    pub history_index: usize,
}

/// Roles, in order; the role number is the index.
const ROLES: &[&str] = &[
    "tabId",
    "url",
    "title",
    "icon",
    "thumbnail",
    "loading",
    "progress",
    "pinned",
    "audible",
    "live",
    "lastActive",
    "engineState",
    "scrollY",
    "desktop",
    "isPrivate",
];

#[derive(Default)]
pub struct TabModelRust {
    pub(crate) private_tabs: bool,
    pub(crate) count: i32,
    pub(crate) active_id: i32,
    pub(crate) active_index: i32,
    pub(crate) closed_count: i32,
    pub(crate) tabs: Vec<Tab>,
    pub(crate) closed: Vec<ClosedTab>,
}

fn row(i: usize) -> i32 {
    i32::try_from(i).unwrap_or(i32::MAX)
}

/// A tab's state for the session file.
fn to_state(t: &Tab) -> TabState {
    let mut entries = t.history.clone();
    let mut index = t.history_index;
    if entries.is_empty() && !t.url.is_empty() {
        entries.push(HistoryEntry {
            url: t.url.clone(),
            title: t.title.clone(),
            scroll_y: t.scroll_y,
        });
        index = 0;
    } else if let Some(e) = entries.get_mut(index) {
        e.scroll_y = t.scroll_y;
    }
    TabState {
        id: i64::from(t.id),
        entries,
        index,
        pinned: t.pinned,
        last_active: t.last_active,
        engine_state: t.engine_state.clone(),
        thumbnail: t.thumbnail.clone(),
    }
}

fn from_state(s: &TabState) -> Tab {
    let cur = s.current().cloned().unwrap_or_default();
    Tab {
        id: i32::try_from(s.id).unwrap_or_else(|_| next_id()),
        url: cur.url,
        title: cur.title,
        thumbnail: s.thumbnail.clone(),
        pinned: s.pinned,
        last_active: s.last_active,
        engine_state: s.engine_state.clone(),
        scroll_y: cur.scroll_y,
        history: s.entries.clone(),
        history_index: s.index,
        ..Tab::default()
    }
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct Patch {
    url: Option<String>,
    title: Option<String>,
    icon: Option<String>,
    thumbnail: Option<String>,
    loading: Option<bool>,
    progress: Option<i32>,
    audible: Option<bool>,
    live: Option<bool>,
    form_dirty: Option<bool>,
    engine_state: Option<String>,
    scroll_y: Option<f64>,
    desktop: Option<bool>,
    history: Option<Vec<HistoryEntry>>,
    history_index: Option<usize>,
}

impl Patch {
    /// Applies the patch; returns the roles that changed.
    #[allow(clippy::float_cmp, reason = "any change of the scroll position counts")]
    fn apply(mut self, t: &mut Tab) -> Vec<i32> {
        let mut roles = Vec::new();
        // A tab whose web view was let go (discarded, or not yet woken)
        // keeps what it showed: the view reporting an empty address, title
        // or state as it lets go must not erase the tab, which wakes from
        // exactly these.
        let parked = !self.live.unwrap_or(t.live);
        if parked {
            for field in [&mut self.url, &mut self.title, &mut self.engine_state] {
                if field.as_deref() == Some("") {
                    *field = None;
                }
            }
        }
        macro_rules! set {
            ($field:ident, $role:expr) => {
                if let Some(v) = self.$field {
                    if t.$field != v {
                        t.$field = v;
                        roles.push($role);
                    }
                }
            };
        }
        set!(url, 1);
        set!(title, 2);
        set!(icon, 3);
        set!(thumbnail, 4);
        set!(loading, 5);
        set!(progress, 6);
        set!(audible, 8);
        set!(live, 9);
        set!(engine_state, 11);
        set!(scroll_y, 12);
        set!(desktop, 13);
        if let Some(v) = self.form_dirty {
            t.form_dirty = v;
        }
        if let Some(mut h) = self.history {
            h.truncate(pacific_core::session::MAX_ENTRIES);
            t.history = h;
        }
        if let Some(i) = self.history_index {
            t.history_index = i.min(t.history.len().saturating_sub(1));
        }
        roles
    }
}

impl qobject::TabModel {
    pub(crate) fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(t) = usize::try_from(index.row())
            .ok()
            .and_then(|r| self.tabs.get(r))
        else {
            return QVariant::default();
        };
        let s = |v: &str| QVariant::from(&QString::from(v));
        match role {
            0 => QVariant::from(&t.id),
            1 => s(&t.url),
            2 => s(&t.title),
            3 => s(&t.icon),
            4 => s(&t.thumbnail),
            5 => QVariant::from(&t.loading),
            6 => QVariant::from(&t.progress),
            7 => QVariant::from(&t.pinned),
            8 => QVariant::from(&t.audible),
            9 => QVariant::from(&t.live),
            #[allow(clippy::cast_precision_loss, reason = "ms timestamps fit an f64")]
            10 => QVariant::from(&(t.last_active as f64)),
            11 => s(&t.engine_state),
            12 => QVariant::from(&t.scroll_y),
            13 => QVariant::from(&t.desktop),
            14 => QVariant::from(&self.private_tabs),
            _ => QVariant::default(),
        }
    }

    pub(crate) fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            row(self.tabs.len())
        }
    }

    #[allow(clippy::unused_self)]
    pub(crate) fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (i, name) in ROLES.iter().enumerate() {
            roles.insert(row(i), QByteArray::from(*name));
        }
        roles
    }

    pub(crate) fn position(&self, id: i32) -> Option<usize> {
        self.tabs.iter().position(|t| t.id == id)
    }

    pub(crate) fn sync_counts(mut self: Pin<&mut Self>) {
        let count = row(self.tabs.len());
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }
        let idx = self.position(self.active_id).map_or(-1, row);
        if self.active_index != idx {
            self.as_mut().rust_mut().active_index = idx;
            self.as_mut().active_index_changed();
        }
        let closed = row(self.closed.len());
        if self.closed_count != closed {
            self.as_mut().rust_mut().closed_count = closed;
            self.as_mut().closed_count_changed();
        }
    }

    pub(crate) fn changed(mut self: Pin<&mut Self>, at: usize, roles: &[i32]) {
        if roles.is_empty() {
            return;
        }
        let idx = self.index(row(at), 0, &QModelIndex::default());
        let mut list = QList::<i32>::default();
        for r in roles {
            list.append(*r);
        }
        self.as_mut().data_changed(&idx, &idx, &list);
    }

    pub(crate) fn insert(mut self: Pin<&mut Self>, at: usize, tab: Tab) {
        let r = row(at);
        // SAFETY: the row is inserted between the begin and end calls.
        unsafe {
            self.as_mut()
                .begin_insert_rows(&QModelIndex::default(), r, r);
        }
        self.as_mut().rust_mut().tabs.insert(at, tab);
        // SAFETY: as above.
        unsafe {
            self.as_mut().end_insert_rows();
        }
    }

    pub(crate) fn remove(mut self: Pin<&mut Self>, at: usize) -> Tab {
        let r = row(at);
        // SAFETY: the row is removed between the begin and end calls.
        unsafe {
            self.as_mut()
                .begin_remove_rows(&QModelIndex::default(), r, r);
        }
        let t = self.as_mut().rust_mut().tabs.remove(at);
        // SAFETY: as above.
        unsafe {
            self.as_mut().end_remove_rows();
        }
        t
    }

    pub(crate) fn set_active(mut self: Pin<&mut Self>, id: i32) {
        if let Some(at) = self.position(id) {
            self.as_mut().rust_mut().tabs[at].last_active = now_ms();
            self.as_mut().changed(at, &[10]);
        }
        if self.active_id != id {
            self.as_mut().rust_mut().active_id = id;
            self.as_mut().active_id_changed();
        }
        self.sync_counts();
    }

    pub(crate) fn add_tab(
        mut self: Pin<&mut Self>,
        url: &QString,
        title: &QString,
        background: bool,
    ) -> i32 {
        let id = next_id();
        let at = self
            .position(self.active_id)
            .map_or(self.tabs.len(), |i| i + 1);
        let tab = Tab {
            id,
            url: url.to_string(),
            title: title.to_string(),
            last_active: now_ms(),
            ..Tab::default()
        };
        self.as_mut().insert(at, tab);
        if background && self.active_id != 0 {
            self.as_mut().sync_counts();
        } else {
            self.as_mut().set_active(id);
        }
        id
    }

    pub(crate) fn close_tab(mut self: Pin<&mut Self>, id: i32) -> i32 {
        let Some(at) = self.position(id) else {
            return self.active_id;
        };
        let tab = self.as_mut().remove(at);
        if !self.private_tabs && !tab.url.is_empty() {
            let closed = ClosedTab {
                tab: to_state(&tab),
                position: at,
                closed_at: now_ms(),
            };
            let list = &mut self.as_mut().rust_mut().closed;
            list.insert(0, closed);
            list.truncate(pacific_core::session::MAX_CLOSED);
        }
        if self.active_id == id {
            // The tab to the left, as Firefox and Chrome do on mobile; the
            // first when the leftmost closed.
            let next = if self.tabs.is_empty() {
                0
            } else {
                self.tabs[at.saturating_sub(1).min(self.tabs.len() - 1)].id
            };
            if next == 0 {
                self.as_mut().rust_mut().active_id = 0;
                self.as_mut().active_id_changed();
                self.as_mut().sync_counts();
            } else {
                self.as_mut().set_active(next);
            }
        } else {
            self.as_mut().sync_counts();
        }
        self.active_id
    }

    pub(crate) fn reopen_closed(mut self: Pin<&mut Self>) -> i32 {
        if self.closed.is_empty() {
            return 0;
        }
        let c = self.as_mut().rust_mut().closed.remove(0);
        let mut tab = from_state(&c.tab);
        tab.id = next_id();
        tab.last_active = now_ms();
        let id = tab.id;
        let at = c.position.min(self.tabs.len());
        self.as_mut().insert(at, tab);
        self.as_mut().set_active(id);
        id
    }

    pub(crate) fn activate(self: Pin<&mut Self>, id: i32) {
        if self.position(id).is_some() {
            self.set_active(id);
        }
    }

    pub(crate) fn update(mut self: Pin<&mut Self>, id: i32, json: &QString) {
        let Some(at) = self.position(id) else {
            return;
        };
        let patch: Patch = match serde_json::from_str(&json.to_string()) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("tab update: {e}");
                return;
            }
        };
        let roles = patch.apply(&mut self.as_mut().rust_mut().tabs[at]);
        self.changed(at, &roles);
    }

    pub(crate) fn move_tab(mut self: Pin<&mut Self>, from: i32, to: i32) {
        let n = self.tabs.len();
        let (Ok(f), Ok(t)) = (usize::try_from(from), usize::try_from(to)) else {
            return;
        };
        if f >= n || t >= n || f == t {
            return;
        }
        // Qt's destination is the row before which to insert, in the
        // numbering before the move.
        let dest = if t > f { t + 1 } else { t };
        // SAFETY: the row moves between the begin and end calls; begin
        // returns false for an impossible move, which the checks exclude.
        let ok = unsafe {
            self.as_mut().begin_move_rows(
                &QModelIndex::default(),
                from,
                from,
                &QModelIndex::default(),
                row(dest),
            )
        };
        if !ok {
            return;
        }
        let tab = self.as_mut().rust_mut().tabs.remove(f);
        self.as_mut().rust_mut().tabs.insert(t, tab);
        // SAFETY: as above.
        unsafe {
            self.as_mut().end_move_rows();
        }
        self.sync_counts();
    }

    /// Pins or unpins a tab. Pinned tabs come first, in the order they
    /// were pinned; unpinning puts the tab right after them.
    pub(crate) fn set_pinned(mut self: Pin<&mut Self>, id: i32, pinned: bool) {
        let Some(at) = self.position(id) else {
            return;
        };
        if self.tabs[at].pinned == pinned {
            return;
        }
        self.as_mut().rust_mut().tabs[at].pinned = pinned;
        self.as_mut().changed(at, &[7]);
        let others_pinned = self.tabs.iter().filter(|t| t.pinned && t.id != id).count();
        let target = others_pinned;
        let target = target.min(self.tabs.len() - 1);
        if target != at {
            self.move_tab(row(at), row(target));
        }
    }

    /// How many tabs are pinned (they come first).
    pub(crate) fn pinned_count(&self) -> i32 {
        row(self.tabs.iter().filter(|t| t.pinned).count())
    }

    pub(crate) fn close_all(mut self: Pin<&mut Self>) {
        let ids: Vec<i32> = self.tabs.iter().map(|t| t.id).collect();
        for id in ids {
            self.as_mut().close_tab(id);
        }
    }

    pub(crate) fn index_of(&self, id: i32) -> i32 {
        self.position(id).map_or(-1, row)
    }

    pub(crate) fn id_at(&self, index: i32) -> i32 {
        usize::try_from(index)
            .ok()
            .and_then(|i| self.tabs.get(i))
            .map_or(0, |t| t.id)
    }

    pub(crate) fn neighbour(&self, id: i32, step: i32) -> i32 {
        let Some(at) = self.position(id) else {
            return 0;
        };
        let target = i64::try_from(at).unwrap_or(0) + i64::from(step);
        usize::try_from(target)
            .ok()
            .and_then(|i| self.tabs.get(i))
            .map_or(0, |t| t.id)
    }

    pub(crate) fn get(&self, id: i32) -> QString {
        let Some(t) = self.position(id).map(|i| &self.tabs[i]) else {
            return QString::from("{}");
        };
        QString::from(
            json!({
                "tabId": t.id, "url": t.url, "title": t.title, "icon": t.icon, "thumbnail": t.thumbnail,
                "loading": t.loading, "progress": t.progress, "pinned": t.pinned, "audible": t.audible,
                "live": t.live, "lastActive": t.last_active, "isPrivate": self.private_tabs,
                "desktop": t.desktop, "scrollY": t.scroll_y,
            })
            .to_string()
            .as_str(),
        )
    }

    pub(crate) fn restore(mut self: Pin<&mut Self>, json: &QString) -> i32 {
        let Ok(mut s) = serde_json::from_str::<Session>(&json.to_string()) else {
            return self.active_id;
        };
        s.normalise();
        let next = i32::try_from(s.next_id).unwrap_or(1);
        NEXT_ID.fetch_max(next.max(1), Ordering::Relaxed);
        let base = self.tabs.len();
        let active = s.tabs.get(s.active).map(|t| t.id);
        for st in &s.tabs {
            let mut tab = from_state(st);
            // A tab id already in use (both models restored, or a page
            // opened before the restore) gets a new one, and lets go of the
            // picture: the file is named after the id the other tab now has.
            if self.position(tab.id).is_some() {
                tab.id = next_id();
                tab.thumbnail.clear();
            }
            let at = self.tabs.len();
            self.as_mut().insert(at, tab);
        }
        forget_shared_thumbnails(&mut s.closed, |id| {
            i32::try_from(id).is_ok_and(|id| self.position(id).is_some())
        });
        self.as_mut().rust_mut().closed = s.closed;
        let active_id = active
            .and_then(|a| i32::try_from(a).ok())
            .filter(|a| self.position(*a).is_some())
            .or_else(|| self.tabs.get(base).map(|t| t.id))
            .unwrap_or(self.active_id);
        if active_id != 0 {
            self.as_mut().set_active(active_id);
        } else {
            self.as_mut().sync_counts();
        }
        self.active_id
    }

    pub(crate) fn session_json(&self) -> QString {
        if self.private_tabs {
            return QString::from("{}");
        }
        let tabs: Vec<TabState> = self.tabs.iter().map(to_state).collect();
        let active = self.position(self.active_id).unwrap_or(0);
        let s = Session {
            tabs,
            active,
            closed: self.closed.clone(),
            next_id: i64::from(NEXT_ID.load(Ordering::Relaxed)),
        };
        QString::from(
            serde_json::to_string(&s)
                .unwrap_or_else(|_| "{}".into())
                .as_str(),
        )
    }

    pub(crate) fn lifecycle_json(&self) -> QString {
        let v: Vec<serde_json::Value> = self
            .tabs
            .iter()
            .map(|t| {
                json!({
                    "id": t.id, "lastActive": t.last_active, "foreground": t.id == self.active_id,
                    "pinned": t.pinned, "audible": t.audible, "formDirty": t.form_dirty, "live": t.live,
                })
            })
            .collect();
        QString::from(serde_json::Value::Array(v).to_string().as_str())
    }

    pub(crate) fn tabs_json(&self) -> QString {
        let v: Vec<serde_json::Value> = self
            .tabs
            .iter()
            .map(|t| json!({ "id": t.id, "url": t.url, "title": t.title, "icon": t.icon }))
            .collect();
        QString::from(serde_json::Value::Array(v).to_string().as_str())
    }
}

/// A closed tab whose id an open tab has (a page opened before the
/// session was restored) forgets its picture, which the open tab's
/// thumbnails overwrite.
fn forget_shared_thumbnails(closed: &mut [ClosedTab], in_use: impl Fn(i64) -> bool) {
    for c in closed.iter_mut().filter(|c| in_use(c.tab.id)) {
        c.tab.thumbnail.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_parked_tab_keeps_what_it_showed() {
        let mut t = Tab {
            id: 1,
            url: "https://news.example/a".into(),
            title: "A".into(),
            live: true,
            ..Tab::default()
        };
        // Discard: the state is saved, then the view lets go and reports
        // an empty address and title.
        let p: Patch = serde_json::from_str(
            r#"{"live":false,"url":"https://news.example/a","title":"A","engineState":"s1","scrollY":300}"#,
        )
        .unwrap();
        p.apply(&mut t);
        let p: Patch = serde_json::from_str(r#"{"url":"","title":"","engineState":""}"#).unwrap();
        assert_eq!(p.apply(&mut t), Vec::<i32>::new());
        assert_eq!(
            (t.url.as_str(), t.title.as_str(), t.engine_state.as_str()),
            ("https://news.example/a", "A", "s1")
        );
        assert!((t.scroll_y - 300.0).abs() < f64::EPSILON);
        // The session keeps the same state for a restore after a crash.
        let s = to_state(&t);
        assert_eq!(s.engine_state, "s1");
        assert_eq!(s.current().unwrap().url, "https://news.example/a");
        // A live tab can go blank (a new-tab page).
        let p: Patch = serde_json::from_str(r#"{"live":true,"url":""}"#).unwrap();
        p.apply(&mut t);
        assert_eq!(t.url, "");
    }

    #[test]
    fn a_closed_tab_does_not_share_an_open_tabs_picture() {
        let closed = |id| ClosedTab {
            tab: TabState {
                id,
                thumbnail: format!("file:///t/tab-{id}.png"),
                ..TabState::default()
            },
            position: 0,
            closed_at: 0,
        };
        let mut c = vec![closed(1), closed(7)];
        forget_shared_thumbnails(&mut c, |id| id == 1);
        assert_eq!(c[0].tab.thumbnail, "");
        assert_eq!(c[1].tab.thumbnail, "file:///t/tab-7.png");
    }

    #[test]
    fn patches_report_changed_roles() {
        let mut t = Tab {
            id: 1,
            url: "https://a/".into(),
            ..Tab::default()
        };
        let p: Patch = serde_json::from_str(
            r#"{"url":"https://a/","title":"A","progress":50,"formDirty":true}"#,
        )
        .unwrap();
        assert_eq!(p.apply(&mut t), [2, 6]);
        assert!(t.form_dirty);
        let p: Patch = serde_json::from_str(
            r#"{"history":[{"url":"https://x/"},{"url":"https://y/"}],"historyIndex":7}"#,
        )
        .unwrap();
        assert_eq!(p.apply(&mut t), Vec::<i32>::new());
        assert_eq!(t.history_index, 1);
    }

    #[test]
    fn session_state_round_trip() {
        let t = Tab {
            id: 4,
            url: "https://b/".into(),
            title: "B".into(),
            scroll_y: 300.0,
            pinned: true,
            history: vec![
                HistoryEntry {
                    url: "https://a/".into(),
                    title: "A".into(),
                    scroll_y: 0.0,
                },
                HistoryEntry {
                    url: "https://b/".into(),
                    title: "B".into(),
                    scroll_y: 0.0,
                },
            ],
            history_index: 1,
            ..Tab::default()
        };
        let s = to_state(&t);
        assert!((s.entries[1].scroll_y - 300.0).abs() < f64::EPSILON);
        let back = from_state(&s);
        assert_eq!(back.url, "https://b/");
        assert!(back.pinned && !back.live);
        assert!((back.scroll_y - 300.0).abs() < f64::EPSILON);
        // A tab that never had a history list still saves its page.
        let plain = Tab {
            id: 5,
            url: "https://c/".into(),
            ..Tab::default()
        };
        assert_eq!(to_state(&plain).entries.len(), 1);
    }
}
