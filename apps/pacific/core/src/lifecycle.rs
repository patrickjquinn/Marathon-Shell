// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Tab lifecycle: which background tabs keep a live web process.
//!
//! Each live tab costs a WebProcess (Atlantic measured about 250 MB RSS
//! per backgrounded tab on the phone). The policy keeps a budget of live
//! tabs, sized from the device's memory, and discards the least recently
//! used background tabs beyond it, or under memory pressure. A discarded
//! tab keeps its thumbnail, URL and back/forward list; it is reloaded
//! when shown. The UI applies the decisions: `terminateWebProcess()` for a
//! discard, `reload()` when a discarded tab comes to the front.
//!
//! Never discarded: the tab in front, tabs playing audio, tabs with a form
//! being edited, and tabs used in the last 30 seconds. Pinned tabs are
//! kept unless the pressure is critical.
//!
//! Budget from `/proc/meminfo` `MemTotal`: 7 GiB or more (the 8 and 12 GB
//! Jolla Phones) keep 5 live tabs, 3.5 GiB or more keep 3, less keep 2.
//! Pressure from `MemAvailable`: below 15% of `MemTotal` (or 600 MiB) is
//! *moderate*, which shrinks the budget to half; below 8% (or 300 MiB) is
//! *critical*, which keeps only the tab in front and the exempt ones.

use serde::Serialize;

/// Memory figures from `/proc/meminfo`, in KiB.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MemInfo {
    pub total_kib: u64,
    pub available_kib: u64,
}

impl MemInfo {
    /// Parses the text of `/proc/meminfo`.
    pub fn parse(text: &str) -> Option<Self> {
        let field = |name: &str| {
            text.lines().find_map(|l| {
                let rest = l.strip_prefix(name)?.strip_prefix(':')?;
                rest.split_whitespace().next()?.parse::<u64>().ok()
            })
        };
        let total_kib = field("MemTotal")?;
        let available_kib = field("MemAvailable").or_else(|| {
            Some(field("MemFree")? + field("Cached").unwrap_or(0) + field("Buffers").unwrap_or(0))
        })?;
        Some(Self {
            total_kib,
            available_kib,
        })
    }

    /// Reads `/proc/meminfo`.
    pub fn read() -> Option<Self> {
        Self::parse(&std::fs::read_to_string("/proc/meminfo").ok()?)
    }

    pub fn pressure(&self) -> Pressure {
        let total = self.total_kib.max(1);
        let avail = self.available_kib;
        if avail * 100 < total * 8 || avail < 300 * 1024 {
            Pressure::Critical
        } else if avail * 100 < total * 15 || avail < 600 * 1024 {
            Pressure::Moderate
        } else {
            Pressure::None
        }
    }

    /// Live tabs to keep without pressure.
    pub fn budget(&self) -> usize {
        const GIB: u64 = 1024 * 1024;
        if self.total_kib >= 7 * GIB {
            5
        } else if self.total_kib * 2 >= 7 * GIB {
            3
        } else {
            2
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Pressure {
    None,
    Moderate,
    Critical,
}

/// What the policy needs to know about a tab.
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent facts about a tab"
)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TabInfo {
    pub id: i64,
    /// Milliseconds since the epoch when it was last in front.
    pub last_active: i64,
    pub foreground: bool,
    pub pinned: bool,
    pub audible: bool,
    /// A form on the page has unsaved input.
    pub form_dirty: bool,
    /// It has a live web process now.
    pub live: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(tag = "action", rename_all = "lowercase")]
pub enum Decision {
    /// Terminate the tab's web process; keep its state for a reload.
    Discard { tab: i64 },
    /// The tab in front was discarded: load it again.
    Reload { tab: i64 },
}

/// Recently used tabs are not discarded.
pub const GRACE_MS: i64 = 30_000;

/// The decisions for `tabs` now. `budget` is the live-tab budget without
/// pressure ([`MemInfo::budget`]).
pub fn decide(tabs: &[TabInfo], budget: usize, pressure: Pressure, now_ms: i64) -> Vec<Decision> {
    let mut out = Vec::new();
    for t in tabs.iter().filter(|t| t.foreground && !t.live) {
        out.push(Decision::Reload { tab: t.id });
    }
    let budget = match pressure {
        Pressure::None => budget.max(1),
        Pressure::Moderate => (budget / 2).max(1),
        Pressure::Critical => 1,
    };
    let exempt = |t: &TabInfo| {
        t.foreground
            || t.audible
            || t.form_dirty
            || now_ms - t.last_active < GRACE_MS
            || (t.pinned && pressure != Pressure::Critical)
    };
    // The tab in front always counts as live (it is, or is being reloaded).
    let live_count = tabs.iter().filter(|t| t.live || t.foreground).count();
    if live_count <= budget {
        return out;
    }
    let mut excess = live_count - budget;
    let mut candidates: Vec<&TabInfo> = tabs.iter().filter(|t| t.live && !exempt(t)).collect();
    // Least recently used first.
    candidates.sort_by_key(|t| (t.last_active, t.id));
    for t in candidates {
        if excess == 0 {
            break;
        }
        out.push(Decision::Discard { tab: t.id });
        excess -= 1;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const MIN: i64 = 60_000;

    fn tab(id: i64, last_active: i64) -> TabInfo {
        TabInfo {
            id,
            last_active,
            foreground: false,
            pinned: false,
            audible: false,
            form_dirty: false,
            live: true,
        }
    }

    #[test]
    fn meminfo_parsing_and_tiers() {
        let text = "MemTotal:        7883256 kB\nMemFree:          200000 kB\nMemAvailable:    3000000 kB\n";
        let m = MemInfo::parse(text).unwrap();
        assert_eq!(m.total_kib, 7_883_256);
        assert_eq!(m.budget(), 5);
        assert_eq!(m.pressure(), Pressure::None);
        let old = MemInfo::parse("MemTotal: 3800000 kB\nMemFree: 100000 kB\nCached: 400000 kB\n")
            .unwrap();
        assert_eq!(old.available_kib, 500_000);
        assert_eq!(old.budget(), 3);
        assert_eq!(old.pressure(), Pressure::Moderate);
        let tiny = MemInfo {
            total_kib: 2_000_000,
            available_kib: 100_000,
        };
        assert_eq!(tiny.budget(), 2);
        assert_eq!(tiny.pressure(), Pressure::Critical);
        assert!(MemInfo::parse("nothing").is_none());
        // Whatever the host has, reading it works on Linux.
        assert!(MemInfo::read().is_some());
    }

    #[test]
    fn discards_least_recently_used_over_budget() {
        let now = 100 * MIN;
        let mut tabs: Vec<_> = (1..=6).map(|i| tab(i, now - (10 - i) * MIN)).collect();
        tabs[5].foreground = true;
        let d = decide(&tabs, 3, Pressure::None, now);
        assert_eq!(
            d,
            [
                Decision::Discard { tab: 1 },
                Decision::Discard { tab: 2 },
                Decision::Discard { tab: 3 }
            ]
        );
        assert!(decide(&tabs, 6, Pressure::None, now).is_empty());
    }

    #[test]
    fn exemptions() {
        let now = 100 * MIN;
        let mut tabs: Vec<_> = (1..=5).map(|i| tab(i, now - (10 - i) * MIN)).collect();
        tabs[0].pinned = true;
        tabs[1].audible = true;
        tabs[2].form_dirty = true;
        tabs[3].last_active = now - 5_000; // within the grace period
        tabs[4].foreground = true;
        assert!(decide(&tabs, 1, Pressure::None, now).is_empty());
        // Critical pressure drops the pinned one, never the others.
        assert_eq!(
            decide(&tabs, 1, Pressure::Critical, now),
            [Decision::Discard { tab: 1 }]
        );
    }

    #[test]
    fn pressure_shrinks_budget_and_front_tab_reloads() {
        let now = 100 * MIN;
        let mut tabs: Vec<_> = (1..=4).map(|i| tab(i, now - (10 - i) * MIN)).collect();
        tabs[3].foreground = true;
        assert!(decide(&tabs, 4, Pressure::None, now).is_empty());
        assert_eq!(
            decide(&tabs, 4, Pressure::Moderate, now),
            [Decision::Discard { tab: 1 }, Decision::Discard { tab: 2 }]
        );
        let all: Vec<_> = decide(&tabs, 4, Pressure::Critical, now);
        assert_eq!(all.len(), 3);
        // A discarded tab brought to the front is reloaded.
        tabs[3].live = false;
        tabs[0].live = false;
        let d = decide(&tabs, 4, Pressure::None, now);
        assert_eq!(d, [Decision::Reload { tab: 4 }]);
    }
}
