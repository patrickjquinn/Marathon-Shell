// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `SuggestionModel`: the address bar's suggestions for `text`
//! (`pacific_core::suggest`). Local results come from the core thread; the
//! engine's suggestions, when allowed, from the network runtime 150 ms
//! after the last keystroke, with a 2 s limit. Answers for older text are
//! dropped.

pub use crate::models::qobject;

use core::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use pacific_core::suggest::{self, Kind, OpenTab, Suggestions};

use crate::worker;

const ROLES: &[&str] = &["kind", "title", "url", "tabId", "engine", "query", "icon"];

#[derive(Default)]
pub struct SuggestionModelRust {
    pub(crate) text: QString,
    pub(crate) remote_enabled: bool,
    pub(crate) tabs: QString,
    pub(crate) autofill: QString,
    pub(crate) count: i32,
    pub(crate) rows: Suggestions,
    pub(crate) generation: u64,
    /// The newest generation, for the network task to see.
    pub(crate) latest: Arc<AtomicU64>,
}

fn kind_name(k: Kind) -> &'static str {
    match k {
        Kind::Visit => "visit",
        Kind::Search => "search",
        Kind::History => "history",
        Kind::Bookmark => "bookmark",
        Kind::Tab => "tab",
        Kind::SearchSuggestion => "suggestion",
        Kind::RecentSearch => "recent",
    }
}

fn open_tabs(json: &str) -> Vec<OpenTab> {
    #[derive(serde::Deserialize)]
    struct T {
        id: i64,
        #[serde(default)]
        url: String,
        #[serde(default)]
        title: String,
    }
    serde_json::from_str::<Vec<T>>(json)
        .unwrap_or_default()
        .into_iter()
        .map(|t| OpenTab {
            id: t.id,
            url: t.url,
            title: t.title,
        })
        .collect()
}

impl qobject::SuggestionModel {
    pub(crate) fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(s) = usize::try_from(index.row())
            .ok()
            .and_then(|r| self.rows.items.get(r))
        else {
            return QVariant::default();
        };
        let q = |v: &str| QVariant::from(&QString::from(v));
        match role {
            0 => q(kind_name(s.kind)),
            1 => q(&s.title),
            2 => q(&s.url),
            3 => QVariant::from(&i32::try_from(s.tab_id).unwrap_or(0)),
            4 => q(&s.engine),
            5 => q(&s.query),
            6 => q(&s.icon),
            _ => QVariant::default(),
        }
    }

    pub(crate) fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            i32::try_from(self.rows.items.len()).unwrap_or(i32::MAX)
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
        let Some(s) = usize::try_from(index)
            .ok()
            .and_then(|r| self.rows.items.get(r))
        else {
            return QString::from("{}");
        };
        QString::from(
            serde_json::json!({
                "kind": kind_name(s.kind), "title": s.title, "url": s.url,
                "tabId": s.tab_id, "engine": s.engine, "query": s.query, "icon": s.icon,
            })
            .to_string()
            .as_str(),
        )
    }

    pub(crate) fn show(mut self: Pin<&mut Self>, generation: u64, rows: Suggestions) {
        if generation != self.generation {
            return;
        }
        self.as_mut().begin_reset_model();
        let autofill = QString::from(rows.autofill.as_str());
        self.as_mut().rust_mut().rows = rows;
        self.as_mut().end_reset_model();
        let count = i32::try_from(self.rows.items.len()).unwrap_or(0);
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }
        if self.autofill != autofill {
            self.as_mut().rust_mut().autofill = autofill;
            self.as_mut().autofill_changed();
        }
    }

    #[allow(
        clippy::needless_pass_by_value,
        reason = "the property setter's signature"
    )]
    pub(crate) fn set_text(mut self: Pin<&mut Self>, text: QString) {
        if self.text == text {
            return;
        }
        self.as_mut().rust_mut().text = text.clone();
        self.as_mut().text_changed();
        self.load(&text);
    }

    pub(crate) fn refresh(self: Pin<&mut Self>) {
        let text = self.text.clone();
        self.load(&text);
    }

    fn load(mut self: Pin<&mut Self>, text: &QString) {
        let generation = self.generation.wrapping_add(1);
        self.as_mut().rust_mut().generation = generation;
        self.latest.store(generation, Ordering::Relaxed);
        let latest = self.latest.clone();
        let text = text.to_string();
        let tabs = open_tabs(&self.tabs.to_string());
        let remote = suggest::may_fetch_remote(&text, self.remote_enabled);
        let thread = self.qt_thread();
        worker::run(move |c| {
            let mut local = c.profile.suggest(&text, &tabs).unwrap_or_default();
            for item in &mut local.items {
                item.icon = c.dirs.favicon_url(&item.icon);
            }
            let engine = c.profile.default_engine().ok();
            let t2 = thread.clone();
            let base = local.clone();
            if thread.queue(move |q| q.show(generation, local)).is_err() {
                return;
            }
            let (Some(engine), true) = (engine, remote) else {
                return;
            };
            let Some(url) = engine.suggest_url_for(&text) else {
                return;
            };
            let Some(rt) = crate::net::runtime() else {
                return;
            };
            rt.spawn(async move {
                tokio::time::sleep(Duration::from_millis(150)).await;
                // Typed on since: drop this request before it is sent.
                if latest.load(Ordering::Relaxed) != generation {
                    return;
                }
                let Ok(resp) = crate::net::get(&url, &[], 64 * 1024, Duration::from_secs(2)).await
                else {
                    return;
                };
                if resp.status != 200 {
                    return;
                }
                let remote = engine.parse_suggestions(&text, &resp.body, 8);
                let mut merged = base;
                suggest::merge_remote(&mut merged, &engine.id, &remote, &engine);
                let _ = t2.queue(move |q| q.show(generation, merged));
            });
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_open_tabs() {
        let t = open_tabs(r#"[{"id":3,"url":"https://a/","title":"A"},{"id":4}]"#);
        assert_eq!(t.len(), 2);
        assert_eq!(t[0].id, 3);
        assert!(open_tabs("nonsense").is_empty());
        assert_eq!(kind_name(Kind::SearchSuggestion), "suggestion");
    }
}
