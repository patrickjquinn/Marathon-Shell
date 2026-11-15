// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Frecency: how often and how recently a page was visited, as one number.
//!
//! The algorithm follows Firefox's exponential-decay frecency (Places,
//! 2024 onwards, `browser/components/urlbar/docs/ranking.md`):
//!
//! 1. Each of the place's 10 most recent visits contributes its *weight*
//!    times `2^(-age / H)`, where `age` is the time since the visit and the
//!    half-life `H` is 30 days. Weights by how the visit happened:
//!    typed in the address bar or chosen from its suggestions 200, opened
//!    from a bookmark, the new-tab page or Pilot 100, a followed link 50,
//!    anything else that is still a deliberate visit (reload, a restored
//!    tab, the target of a redirect) 20. Downloads and redirect sources
//!    weigh 0.
//! 2. The sum is scaled by `visit_count / sampled visits`, so a place
//!    visited 300 times scores higher than one visited 10 times with the
//!    same recent visits.
//! 3. A bookmarked place's score is doubled.
//! 4. The score is *stored as a date*: `frecency = now + H * log2(score)`,
//!    in milliseconds. Because every score decays at the same rate, the
//!    order of the stored dates is the order of the current scores, so
//!    nothing needs recomputing as time passes: a place is recomputed only
//!    when it is visited, bookmarked or unbookmarked. The current score is
//!    `2^((frecency - now) / H)` ([`score_at`]).
//!
//! Address-bar ranking combines this score with how well a place matches
//! the typed text (suggest.rs).

/// Half-life of a visit's contribution: 30 days, in milliseconds.
pub const HALF_LIFE_MS: f64 = 30.0 * 24.0 * 3600.0 * 1000.0;

/// Visits sampled per place.
pub const SAMPLE: usize = 10;

/// How a visit happened. Stored as an integer in `visits.transition`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Transition {
    /// A followed link or a page's own navigation.
    Link,
    /// Typed in the address bar, or a suggestion chosen there.
    Typed,
    /// From a bookmark, the new-tab page's top sites, or Pilot.
    Bookmark,
    Reload,
    /// The target of a redirect.
    Redirect,
    /// A tab restored from the session.
    Restore,
    Download,
    /// The source of a redirect (never shown in history).
    RedirectSource,
}

impl Transition {
    pub fn to_i64(self) -> i64 {
        match self {
            Self::Link => 0,
            Self::Typed => 1,
            Self::Bookmark => 2,
            Self::Reload => 3,
            Self::Redirect => 4,
            Self::Restore => 5,
            Self::Download => 6,
            Self::RedirectSource => 7,
        }
    }

    pub fn from_i64(v: i64) -> Self {
        match v {
            1 => Self::Typed,
            2 => Self::Bookmark,
            3 => Self::Reload,
            4 => Self::Redirect,
            5 => Self::Restore,
            6 => Self::Download,
            7 => Self::RedirectSource,
            _ => Self::Link,
        }
    }

    /// The weight of one visit of this kind (step 1 above).
    pub fn weight(self) -> f64 {
        match self {
            Self::Typed => 200.0,
            Self::Bookmark => 100.0,
            Self::Link => 50.0,
            Self::Reload | Self::Redirect | Self::Restore => 20.0,
            Self::Download | Self::RedirectSource => 0.0,
        }
    }
}

/// The decayed score of a place at `now_ms`, from its most recent visits
/// (`(time ms, transition)`, any order; only the newest [`SAMPLE`] count),
/// its total visit count and whether it is bookmarked.
pub fn score(visits: &[(i64, Transition)], visit_count: i64, bookmarked: bool, now_ms: i64) -> f64 {
    let mut recent: Vec<&(i64, Transition)> = visits.iter().collect();
    recent.sort_by_key(|v| std::cmp::Reverse(v.0));
    recent.truncate(SAMPLE);
    let sampled = recent.len();
    #[allow(
        clippy::cast_precision_loss,
        reason = "visit times and counts are far below 2^52"
    )]
    let mut sum: f64 = recent
        .iter()
        .map(|(t, tr)| {
            let age = (now_ms - t).max(0) as f64;
            tr.weight() * (-age / HALF_LIFE_MS).exp2()
        })
        .sum();
    if sampled > 0 {
        #[allow(clippy::cast_precision_loss, reason = "small counts")]
        let scale = (visit_count.max(1) as f64) / (sampled as f64);
        sum *= scale.max(1.0);
    }
    if bookmarked {
        // A bookmark with no visits still deserves a place in the ranking.
        sum = if sum > 0.0 {
            sum * 2.0
        } else {
            Transition::Bookmark.weight()
        };
    }
    sum
}

/// The score stored as a date (step 4); 0 for a score of 0.
pub fn to_date(score: f64, now_ms: i64) -> f64 {
    if score <= 0.0 {
        return 0.0;
    }
    #[allow(
        clippy::cast_precision_loss,
        reason = "ms timestamps fit an f64 exactly"
    )]
    let now = now_ms as f64;
    now + HALF_LIFE_MS * score.log2()
}

/// The current score of a place whose stored frecency date is `date`.
pub fn score_at(date: f64, now_ms: i64) -> f64 {
    if date <= 0.0 {
        return 0.0;
    }
    #[allow(
        clippy::cast_precision_loss,
        reason = "ms timestamps fit an f64 exactly"
    )]
    let now = now_ms as f64;
    ((date - now) / HALF_LIFE_MS).exp2()
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAY: i64 = 24 * 3600 * 1000;

    #[test]
    fn decays_by_half_every_thirty_days() {
        let now = 1_000 * DAY;
        let fresh = score(&[(now, Transition::Typed)], 1, false, now);
        let old = score(&[(now - 30 * DAY, Transition::Typed)], 1, false, now);
        assert!((fresh - 200.0).abs() < 1e-9);
        assert!((old - 100.0).abs() < 1e-6);
    }

    #[test]
    fn typed_beats_link_and_more_visits_beat_fewer() {
        let now = 1_000 * DAY;
        let typed = score(&[(now - DAY, Transition::Typed)], 1, false, now);
        let link = score(&[(now - DAY, Transition::Link)], 1, false, now);
        assert!(typed > link);
        let visits: Vec<_> = (0..10).map(|i| (now - i * DAY, Transition::Link)).collect();
        let few = score(&visits, 10, false, now);
        let many = score(&visits, 100, false, now);
        assert!((many / few - 10.0).abs() < 1e-9);
    }

    #[test]
    fn only_ten_newest_visits_count() {
        let now = 1_000 * DAY;
        let mut visits: Vec<_> = (0..10).map(|i| (now - i * DAY, Transition::Link)).collect();
        let base = score(&visits, 10, false, now);
        // An eleventh, older but heavy visit is not sampled (count fixed).
        visits.push((now - 50 * DAY, Transition::Typed));
        assert!((score(&visits, 10, false, now) - base).abs() < 1e-9);
    }

    #[test]
    fn bookmarks_count_double_and_alone() {
        let now = 1_000 * DAY;
        let s = score(&[(now, Transition::Link)], 1, true, now);
        assert!((s - 100.0).abs() < 1e-9);
        assert!((score(&[], 0, true, now) - 100.0).abs() < 1e-9);
        assert!(score(&[], 0, false, now).abs() < f64::EPSILON);
    }

    #[test]
    fn stored_date_round_trips_and_keeps_order() {
        let now = 2_000 * DAY;
        for s in [1.0, 37.5, 200.0, 9000.0] {
            let d = to_date(s, now);
            assert!((score_at(d, now) - s).abs() / s < 1e-9);
            // Thirty days later the score has halved.
            assert!((score_at(d, now + 30 * DAY) - s / 2.0).abs() / s < 1e-9);
        }
        assert!(to_date(10.0, now) < to_date(20.0, now));
        // A visit long ago with a big score vs a recent small one: the
        // dates order them as their current scores do.
        let a = to_date(
            score(&[(now - 90 * DAY, Transition::Typed)], 50, false, now),
            now,
        );
        let b = to_date(score(&[(now, Transition::Link)], 1, false, now), now);
        let later = now + 10 * DAY;
        assert_eq!(a > b, score_at(a, later) > score_at(b, later));
        assert!(to_date(0.0, now).abs() < f64::EPSILON);
    }

    #[test]
    fn transitions_round_trip() {
        for t in [
            Transition::Link,
            Transition::Typed,
            Transition::Bookmark,
            Transition::Reload,
            Transition::Redirect,
            Transition::Restore,
            Transition::Download,
            Transition::RedirectSource,
        ] {
            assert_eq!(Transition::from_i64(t.to_i64()), t);
        }
    }
}
