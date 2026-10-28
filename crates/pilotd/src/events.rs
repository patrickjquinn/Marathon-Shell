// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Pilot in the Events view (spec section 8.2, "Events view tab"), through
//! the one public extension point Lipstick has for it: notifications.
//!
//! Lipstick's Events view has no API for a third-party tab; its tabs, and
//! the edge gestures, are QML in the closed `lipstick-jolla-home-qt5`
//! (see ../lipstick/README.md). What any package may do is post
//! notifications and install a category definition
//! (`/usr/share/lipstick/notificationcategories/<category>.conf`, read by
//! the open-source lipstick library). So Pilot keeps one entry in the
//! Events view, in its own category (`x-shipwright.pilot.triage`):
//! "2 to act on now, 3 for today", with the titles, updated in place as
//! triage results arrive. Tapping it calls `OpenEvents`, which opens the
//! Pilot app's events page and clears the entry.
//!
//! It never pops up, sounds or wakes the screen (urgency low, no preview
//! hints, no feedback; spoken nudges are triage's own, section 5.3), and
//! its titles stay off the lock screen (no public visibility). It exists
//! only while triage is consented to and the privacy switch is off.

use std::sync::{Arc, Mutex};

use crate::adapters::Adapters;
use crate::privacy::Offline;
use crate::settings::Settings;
use crate::store::{self, Store, TriageItem};

pub const CATEGORY: &str = "x-shipwright.pilot.triage";
/// The tap: `service path interface method`, as mlite's `MRemoteAction`
/// parses it (no arguments).
pub const OPEN_ACTION: &str =
    "org.shipwright.Pilot /org/shipwright/Pilot org.shipwright.Pilot1 OpenEvents";
const ID_KEY: &str = "events.notification";
const SEEN_KEY: &str = "events.seen_ms";
/// Only the last day's results count.
const WINDOW_MS: i64 = 86_400_000;
/// Titles listed per bucket.
const TITLES: usize = 3;

/// The entry's text, from triage results newer than `seen_ms`; `None` when
/// nothing needs the person.
pub fn summary(items: &[TriageItem], seen_ms: i64, now_ms: i64) -> Option<(String, String)> {
    let fresh: Vec<&TriageItem> = items
        .iter()
        .filter(|i| i.ts_ms > seen_ms && i.ts_ms > now_ms - WINDOW_MS)
        .collect();
    let of = |bucket: &str| -> Vec<&TriageItem> {
        fresh
            .iter()
            .filter(|i| i.bucket == bucket)
            .copied()
            .collect()
    };
    let (now, today) = (of("act_now"), of("today"));
    if now.is_empty() && today.is_empty() {
        return None;
    }
    let count = |n: usize, what: &str| format!("{n} {what}");
    let mut heads = Vec::new();
    if !now.is_empty() {
        heads.push(count(now.len(), "to act on now"));
    }
    if !today.is_empty() {
        heads.push(count(today.len(), "for today"));
    }
    let titles: Vec<String> = now
        .iter()
        .chain(today.iter())
        .take(TITLES)
        .map(|i| i.title.chars().take(60).collect())
        .collect();
    Some((heads.join(", "), titles.join(" · ")))
}

pub struct EventsEntry {
    /// `[events] notification`.
    notification: bool,
    store: Arc<Store>,
    adapters: Arc<Adapters>,
    settings: Arc<Mutex<Settings>>,
    offline: Offline,
    /// Serialises updates so two triage results cannot race.
    lock: tokio::sync::Mutex<()>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

impl EventsEntry {
    pub fn new(
        notification: bool,
        store: Arc<Store>,
        adapters: Arc<Adapters>,
        settings: Arc<Mutex<Settings>>,
        offline: Offline,
    ) -> EventsEntry {
        EventsEntry {
            notification,
            store,
            adapters,
            settings,
            offline,
            lock: tokio::sync::Mutex::new(()),
        }
    }

    fn id(&self) -> u32 {
        self.store
            .meta(ID_KEY)
            .ok()
            .flatten()
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    }

    fn seen(&self) -> i64 {
        self.store
            .meta(SEEN_KEY)
            .ok()
            .flatten()
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    }

    fn remember(&self, id: u32) {
        if let Err(e) = self.store.set_meta(ID_KEY, &id.to_string()) {
            log::warn!("events entry: {e}");
        }
    }

    async fn close(&self) {
        let id = self.id();
        if id != 0 {
            if let Err(e) = self.adapters.notifier.close(id).await {
                log::debug!("events entry: closing: {e}");
            }
            self.remember(0);
        }
    }

    /// What needs the person now: `(summary, titles)`, or `None` (also
    /// without triage consent or with the privacy switch on). The widget
    /// reads this through `EventsSummary`.
    pub fn current(&self) -> Option<(String, String)> {
        if !lock(&self.settings).consent.triage || self.offline.is_offline() {
            return None;
        }
        let items = self.store.triage(0).unwrap_or_default();
        summary(&items, self.seen(), store::now_ms())
    }

    /// Shows, updates or removes the notification from the triage list.
    pub async fn refresh(&self) {
        let _guard = self.lock.lock().await;
        let current = if self.notification {
            self.current()
        } else {
            None
        };
        let Some((summary, body)) = current else {
            return self.close().await;
        };
        let hints = [
            ("category", CATEGORY.to_owned()),
            ("urgency", "0".to_owned()),
            ("x-nemo-remote-action-default", OPEN_ACTION.to_owned()),
            ("x-nemo-user-removable", "true".to_owned()),
        ];
        match self
            .adapters
            .notifier
            .show(self.id(), &summary, &body, &hints)
            .await
        {
            Ok(id) => self.remember(id),
            Err(e) => log::debug!("events entry: {e}"),
        }
    }

    /// The person opened the events page: what was there is seen.
    pub async fn opened(&self) {
        let _guard = self.lock.lock().await;
        if let Err(e) = self.store.set_meta(SEEN_KEY, &store::now_ms().to_string()) {
            log::warn!("events entry: {e}");
        }
        self.close().await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(ts: i64, bucket: &str, title: &str) -> TriageItem {
        TriageItem {
            id: 0,
            ts_ms: ts,
            source: "sms".into(),
            app: "Messages".into(),
            title: title.into(),
            body: "never shown".into(),
            bucket: bucket.into(),
            urgency: 1.0,
            interrupt: 0.5,
        }
    }

    #[test]
    fn counts_the_unseen_and_lists_titles() {
        let now = 10 * WINDOW_MS;
        let items = [
            item(now - 1, "act_now", "Anna Virtanen"),
            item(now - 2, "today", "Dentist"),
            item(now - 3, "today", "Bank"),
            item(now - 4, "later", "Newsletter"),
            item(now - 5, "act_now", "Old, seen"),
            item(now - WINDOW_MS - 1, "act_now", "Yesterday"),
        ];
        let (s, b) = summary(&items, now - 5, now).unwrap();
        assert_eq!(s, "1 to act on now, 2 for today");
        assert_eq!(b, "Anna Virtanen · Dentist · Bank");
        assert!(!b.contains("never shown"));
        assert_eq!(
            summary(&items[3..4], 0, now),
            None,
            "later and ignore are not news"
        );
        assert_eq!(summary(&items, now, now), None, "all seen");
    }
}
