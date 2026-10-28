// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Threshold calibration (spec section 5.2: "calibrate against logged
//! outcomes before release"; roadmap phase 3). Reads the decision log on
//! the device (`pilotd --calibrate`) and reports, per route, how often a
//! turn was corrected, cancelled or declined, and for the deterministic
//! route the same by intent confidence. Nothing is sent anywhere; testers
//! share the report if they choose.
//!
//! The suggestion only ever keeps or raises `intent_confidence`: below the
//! current threshold turns go to Qwen, so the log has no handler outcomes
//! there to judge a lower value by.

use serde::Serialize;

use crate::route::Thresholds;
use crate::store::Decision;

/// Handler turns above the suggested threshold may be corrected at most
/// this often ...
pub const MAX_CORRECTION: f64 = 0.05;
/// ... judged on at least this many turns.
pub const MIN_TURNS: usize = 30;
const BAND: f64 = 0.05;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RouteStats {
    pub route: String,
    /// Turns with a final outcome (not pending or dropped).
    pub turns: usize,
    /// Corrected, cancelled or declined.
    pub corrected: usize,
    pub failed: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Band {
    pub from: f64,
    pub to: f64,
    pub turns: usize,
    pub corrected: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Report {
    pub routes: Vec<RouteStats>,
    /// Handler turns by intent confidence, from the current threshold up.
    pub handler_bands: Vec<Band>,
    pub intent_confidence: f64,
    /// `None` when the log cannot support a value yet.
    pub suggested_intent_confidence: Option<f64>,
    pub note: String,
}

fn settled(d: &Decision) -> bool {
    !matches!(d.outcome.as_str(), "pending" | "dropped")
}

fn corrected(d: &Decision) -> bool {
    matches!(d.outcome.as_str(), "corrected" | "cancelled" | "declined")
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

pub fn report(log: &[Decision], t: &Thresholds) -> Report {
    let mut by_route: std::collections::BTreeMap<&str, RouteStats> =
        std::collections::BTreeMap::new();
    for d in log.iter().filter(|d| settled(d)) {
        let r = by_route.entry(&d.route).or_insert_with(|| RouteStats {
            route: d.route.clone(),
            turns: 0,
            corrected: 0,
            failed: 0,
        });
        r.turns += 1;
        r.corrected += usize::from(corrected(d));
        r.failed += usize::from(d.outcome == "failed");
    }
    let routes: Vec<RouteStats> = by_route.into_values().collect();

    let handler: Vec<&Decision> = log
        .iter()
        .filter(|d| settled(d) && d.route == "handler")
        .collect();
    let mut bands = Vec::new();
    let mut from = t.intent_confidence;
    while from < 1.0 - 1e-9 {
        let to = round2((from + BAND).min(1.0));
        let last = to >= 1.0;
        let inside: Vec<&&Decision> = handler
            .iter()
            .filter(|d| d.confidence >= from && (d.confidence < to || last))
            .collect();
        bands.push(Band {
            from: round2(from),
            to,
            turns: inside.len(),
            corrected: inside.iter().filter(|d| corrected(d)).count(),
        });
        from = to;
    }

    // The lowest band start where everything at or above it is good enough.
    let mut suggested = None;
    for (i, b) in bands.iter().enumerate() {
        let (n, c) = bands[i..]
            .iter()
            .fold((0, 0), |(n, c), x| (n + x.turns, c + x.corrected));
        #[allow(clippy::cast_precision_loss, reason = "turn counts are far below 2^52")]
        if n >= MIN_TURNS && (c as f64) <= MAX_CORRECTION * n as f64 {
            suggested = Some(b.from);
            break;
        }
    }
    let note = match suggested {
        _ if handler.len() < MIN_TURNS => format!(
            "{} handler turns logged; at least {MIN_TURNS} are needed.",
            handler.len()
        ),
        Some(s) if (s - t.intent_confidence).abs() < 1e-9 => {
            "The current threshold holds; lower values cannot be judged from this log.".into()
        }
        Some(s) => format!("Raise intent_confidence to {s:.2}."),
        None => "Handler turns are corrected too often at every confidence; check the intents and their parsers.".into(),
    };
    Report {
        routes,
        handler_bands: bands,
        intent_confidence: t.intent_confidence,
        suggested_intent_confidence: suggested,
        note,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(route: &str, confidence: f64, outcome: &str) -> Decision {
        Decision {
            turn: String::new(),
            ts_ms: 0,
            top_intent: "timer".into(),
            confidence,
            second_intent: None,
            needs_generation: 0.0,
            ambiguity: 0.0,
            route: route.into(),
            outcome: outcome.into(),
        }
    }

    #[test]
    fn suggests_raising_when_low_confidence_turns_get_corrected() {
        let mut log = Vec::new();
        // 0.85 to 0.90: 10 turns, 4 corrected. Above 0.90: 40 turns, 1.
        for i in 0..10 {
            log.push(d("handler", 0.87, if i < 4 { "corrected" } else { "done" }));
        }
        for i in 0..40 {
            log.push(d(
                "handler",
                0.96,
                if i == 0 { "cancelled" } else { "done" },
            ));
        }
        log.push(d("qwen", 0.4, "failed"));
        log.push(d("handler", 0.99, "pending"));
        let r = report(&log, &Thresholds::default());
        assert_eq!(r.suggested_intent_confidence, Some(0.9));
        assert_eq!(r.note, "Raise intent_confidence to 0.90.");
        assert_eq!(r.handler_bands.len(), 3);
        assert_eq!(
            (r.handler_bands[0].turns, r.handler_bands[0].corrected),
            (10, 4)
        );
        assert_eq!(
            (r.handler_bands[2].turns, r.handler_bands[2].corrected),
            (40, 1)
        );
        let q = r.routes.iter().find(|x| x.route == "qwen").unwrap();
        assert_eq!((q.turns, q.failed), (1, 1));
    }

    #[test]
    fn too_little_data_suggests_nothing() {
        let log = vec![d("handler", 0.95, "done"); 5];
        let r = report(&log, &Thresholds::default());
        assert_eq!(r.suggested_intent_confidence, None);
        assert!(r.note.starts_with("5 handler turns"), "{}", r.note);
    }
}
