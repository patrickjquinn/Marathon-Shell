// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Routing policy (spec section 5.2). Jev returns probabilities; this code
//! decides. Thresholds are configuration with the spec's initial values.

use serde::{Deserialize, Serialize};

use crate::jev::{Answer, Answers};

#[derive(Debug, Clone, Copy, PartialEq, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct Thresholds {
    /// Deterministic route: `intent.confidence >=` this ...
    pub intent_confidence: f64,
    /// ... and `needs_generation <` this ...
    pub handler_max_generation: f64,
    /// ... and `ambiguity <` this. Also: `ambiguity >=` this clarifies.
    pub ambiguity: f64,
    /// Qwen when `needs_generation >=` this.
    pub qwen_min_generation: f64,
    /// Search the web before Qwen answers when Jev's `needs_web >=` this.
    pub web_first: f64,
}

impl Default for Thresholds {
    fn default() -> Self {
        Thresholds {
            intent_confidence: 0.85,
            handler_max_generation: 0.3,
            ambiguity: 1.0,
            qwen_min_generation: 0.6,
            web_first: 0.6,
        }
    }
}

/// The three answers routing needs, extracted and typed.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Decision {
    pub intent: String,
    pub confidence: f64,
    /// The top two intents with their probabilities.
    pub top_two: Vec<(String, f64)>,
    pub needs_generation: f64,
    pub ambiguity: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "route", rename_all = "snake_case")]
pub enum Route {
    /// Known intent above threshold: deterministic handler, no LLM.
    Handler { intent: String },
    /// Missing required detail: one templated question.
    Clarify { intent: String },
    /// Open-ended or generation needed.
    Qwen,
    /// Anything else: Qwen with Jev's top two intents as hints.
    QwenWithHints { hints: Vec<(String, f64)> },
}

impl Route {
    pub fn label(&self) -> &'static str {
        match self {
            Route::Handler { .. } => "handler",
            Route::Clarify { .. } => "clarify",
            Route::Qwen => "qwen",
            Route::QwenWithHints { .. } => "qwen_hints",
        }
    }
}

impl Decision {
    /// Reads `intent`, `needs_generation` and `ambiguity` from Jev's
    /// answers; `None` if any is missing or mistyped.
    pub fn from_answers(a: &Answers) -> Option<Decision> {
        let Some(Answer::Choice {
            distribution,
            confidence,
        }) = a.get("intent")
        else {
            return None;
        };
        let Some(Answer::Noul { p }) = a.get("needs_generation") else {
            return None;
        };
        let Some(Answer::Score { value, .. }) = a.get("ambiguity") else {
            return None;
        };
        let (intent, _) = distribution.first()?;
        Some(Decision {
            intent: intent.clone(),
            confidence: *confidence,
            top_two: distribution.iter().take(2).cloned().collect(),
            needs_generation: *p,
            ambiguity: *value,
        })
    }
}

/// Section 5.2, evaluated top to bottom.
pub fn route(d: &Decision, t: &Thresholds) -> Route {
    if d.confidence >= t.intent_confidence
        && d.needs_generation < t.handler_max_generation
        && d.ambiguity < t.ambiguity
    {
        return Route::Handler {
            intent: d.intent.clone(),
        };
    }
    // A templated question only helps an action missing a detail (an
    // alarm with no time). An open question Jev finds ambiguous ("what's
    // in the news?") is answered; the model asks back itself if it must.
    // Only the intents with a templated question (a deterministic handler's
    // missing detail): for the rest the template was "Could you tell me a
    // bit more?" to "draft an e-mail to test@example.com saying I'm late".
    if d.ambiguity >= t.ambiguity && crate::intents::DETERMINISTIC.contains(&d.intent.as_str()) {
        return Route::Clarify {
            intent: d.intent.clone(),
        };
    }
    if d.intent == "open_ended" || d.needs_generation >= t.qwen_min_generation {
        return Route::Qwen;
    }
    Route::QwenWithHints {
        hints: d.top_two.clone(),
    }
}

/// [`route`], except that a confident intent whose slots the device parsed
/// in full (`parsed`: a reminder's text and time, a timer's duration) goes
/// to its handler whatever `needs_generation` says. Jev rates plain "remind
/// me to stretch in 5 minutes" around 0.55 on generation, so the spec's
/// table sent every reminder and timer through Qwen, which took longer and
/// sometimes titled the reminder "time". Jev's ambiguity still asks first,
/// but only when something is left open (`open`: a time that could be
/// morning or evening); with everything parsed there is nothing to ask.
pub fn route_parsed(d: &Decision, t: &Thresholds, parsed: bool, open: bool) -> Route {
    if parsed && d.confidence >= t.intent_confidence && (d.ambiguity < t.ambiguity || !open) {
        return Route::Handler {
            intent: d.intent.clone(),
        };
    }
    route(d, t)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(intent: &str, conf: f64, gen: f64, amb: f64) -> Decision {
        Decision {
            intent: intent.into(),
            confidence: conf,
            top_two: vec![(intent.into(), conf), ("alarm".into(), 1.0 - conf)],
            needs_generation: gen,
            ambiguity: amb,
        }
    }

    #[test]
    fn spec_table_rows() {
        let t = Thresholds::default();
        assert_eq!(
            route(&d("timer", 0.85, 0.29, 0.99), &t),
            Route::Handler {
                intent: "timer".into()
            }
        );
        assert_eq!(
            route(&d("timer", 0.95, 0.1, 1.0), &t),
            Route::Clarify {
                intent: "timer".into()
            }
        );
        assert_eq!(
            route(&d("open_ended", 0.95, 0.1, 0.2), &t),
            Route::Handler {
                intent: "open_ended".into()
            }
        );
        assert_eq!(route(&d("open_ended", 0.7, 0.1, 0.2), &t), Route::Qwen);
        // An open question is never met with "tell me more".
        assert_eq!(route(&d("open_ended", 1.0, 0.94, 1.06), &t), Route::Qwen);
        assert_eq!(route(&d("timer", 0.95, 0.6, 0.2), &t), Route::Qwen);
        assert!(matches!(
            route(&d("timer", 0.84, 0.1, 0.2), &t),
            Route::QwenWithHints { .. }
        ));
        assert!(matches!(
            route(&d("timer", 0.95, 0.3, 0.2), &t),
            Route::QwenWithHints { .. }
        ));
    }

    #[test]
    fn parsed_slots_skip_the_generation_score() {
        let t = Thresholds::default();
        let handler = Route::Handler {
            intent: "reminder".into(),
        };
        let r = |conf, amb, parsed, open| {
            route_parsed(&d("reminder", conf, 0.57, amb), &t, parsed, open)
        };
        assert_eq!(r(0.98, 0.3, true, false), handler);
        assert!(matches!(
            r(0.98, 0.3, false, false),
            Route::QwenWithHints { .. }
        ));
        assert!(matches!(
            r(0.80, 0.3, true, false),
            Route::QwenWithHints { .. }
        ));
        // Jev unsure, but nothing left open: the handler.
        assert_eq!(r(0.98, 1.1, true, false), handler);
        // Jev unsure and a morning-or-evening time: ask.
        assert_eq!(
            r(0.98, 1.1, true, true),
            Route::Clarify {
                intent: "reminder".into()
            }
        );
    }
}
