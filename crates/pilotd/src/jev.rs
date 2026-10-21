// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The decision layer (spec section 5): typed questions in, typed answers
//! with probabilities out, no text generation.
//!
//! Two implementations behind [`JevClient`]:
//!
//! - [`HttpJev`]: the hosted Jev API (`POST /v1/systemone`,
//!   through the Pilot relay by default), in its published schema
//!   (`https://api.typesafe.ai/openapi.json`, checked 2026-10-03 against
//!   the live API): [`wire_questions`] sends a choice's options as the keys
//!   of `criteria`, a score's legend as the `criteria` list and each
//!   question's text as `instructions`; [`parse_answers`] reads
//!   `{"answers": {name: answer}}` with a choice as
//!   `{"choice", "confidence", "probabilities": {option: p}}`, a noul as
//!   `{"noul": p}` and a score as `{"score", "confidence"}`.
//! - [`ScoreJev`]: the Lighthouse scorer (section 10.1): a small open model
//!   behind SGLang's `/v1/score`, one request per question, using the
//!   restricted softmax over label tokens for Choice, Noul and Score.
//!
//! Every answer is checked before use (principle 2): probabilities in
//! [0, 1], choice options from the question, every question answered.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::remote::{Remote, RemoteError};

/// One typed question.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum Question {
    /// `criteria` is the question; `descriptions`, when not empty, say when
    /// each option applies (parallel to `options`). Jev's guidance:
    /// describe situations, not degrees.
    Choice {
        options: Vec<String>,
        criteria: String,
        descriptions: Vec<String>,
    },
    /// `criteria` is the literal yes/no question; `yes` and `no`, when not
    /// empty, describe what counts as each.
    Noul {
        criteria: String,
        yes: String,
        no: String,
    },
    Score {
        legend: Vec<String>,
        criteria: String,
    },
}

/// Jev Choice is capped at 255 options (section 5).
pub const MAX_CHOICE_OPTIONS: usize = 255;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DecideRequest {
    /// Redacted state: utterance and context.
    pub state: Value,
    pub questions: BTreeMap<String, Question>,
}

/// One typed answer.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub enum Answer {
    /// Options with probabilities, most likely first.
    Choice {
        distribution: Vec<(String, f64)>,
        confidence: f64,
    },
    /// Probability of yes.
    Noul { p: f64 },
    /// Probability-weighted position on the legend (0 = first entry).
    Score { value: f64, confidence: f64 },
}

impl Answer {
    pub fn top(&self) -> Option<&str> {
        match self {
            Answer::Choice { distribution, .. } => distribution.first().map(|(o, _)| o.as_str()),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Default, Serialize)]
pub struct Answers(pub BTreeMap<String, Answer>);

impl Answers {
    pub fn get(&self, name: &str) -> Option<&Answer> {
        self.0.get(name)
    }
}

#[async_trait]
pub trait JevClient: Send + Sync {
    async fn decide(&self, req: &DecideRequest, purpose: &str) -> Result<Answers, RemoteError>;
    /// Provider name for the egress log and settings.
    fn provider(&self) -> &str;
}

fn bad(provider: &str, message: impl Into<String>) -> RemoteError {
    RemoteError::Decode {
        provider: provider.to_owned(),
        message: message.into(),
    }
}

fn prob(provider: &str, what: &str, v: Option<&Value>) -> Result<f64, RemoteError> {
    let p = v
        .and_then(Value::as_f64)
        .ok_or_else(|| bad(provider, format!("{what}: missing number")))?;
    if !(0.0..=1.0).contains(&p) {
        return Err(bad(provider, format!("{what}: {p} is not a probability")));
    }
    Ok(p)
}

/// The questions in Jev's request schema. A choice option has no
/// description (null): Jev reads it by its name.
pub fn wire_questions(questions: &BTreeMap<String, Question>) -> Value {
    let wire = |q: &Question| match q {
        Question::Choice {
            options,
            criteria,
            descriptions,
        } => json!({
            "type": "choice",
            "instructions": criteria,
            "criteria": options
                .iter()
                .enumerate()
                .map(|(i, o)| {
                    let d = descriptions.get(i).filter(|d| !d.is_empty());
                    (o.clone(), d.map_or(Value::Null, |d| Value::from(d.as_str())))
                })
                .collect::<serde_json::Map<_, _>>(),
        }),
        Question::Noul { criteria, yes, no } => {
            if yes.is_empty() && no.is_empty() {
                json!({"type": "noul", "instructions": criteria})
            } else {
                json!({"type": "noul", "instructions": criteria,
                       "criteria": {"true": yes, "false": no}})
            }
        }
        Question::Score { legend, criteria } => json!({
            "type": "score",
            "instructions": criteria,
            "criteria": legend,
        }),
    };
    Value::Object(
        questions
            .iter()
            .map(|(name, q)| (name.clone(), wire(q)))
            .collect(),
    )
}

/// Checks and converts a Jev reply against the questions asked.
pub fn parse_answers(
    provider: &str,
    req: &DecideRequest,
    body: &Value,
) -> Result<Answers, RemoteError> {
    let map = body
        .get("answers")
        .and_then(Value::as_object)
        .ok_or_else(|| bad(provider, "answers is not an object"))?;
    let mut out = BTreeMap::new();
    for (name, q) in &req.questions {
        let a = map
            .get(name)
            .ok_or_else(|| bad(provider, format!("no answer for {name}")))?;
        let answer = match q {
            Question::Choice { options, .. } => {
                let mut dist: Vec<(String, f64)> = match a.get("probabilities") {
                    Some(Value::Object(o)) => o
                        .iter()
                        .map(|(k, v)| Ok((k.clone(), prob(provider, name, Some(v))?)))
                        .collect::<Result<_, RemoteError>>()?,
                    _ => return Err(bad(provider, format!("{name}: no probabilities"))),
                };
                if let Some((unknown, _)) = dist.iter().find(|(o, _)| !options.contains(o)) {
                    return Err(bad(provider, format!("{name}: unknown option {unknown}")));
                }
                if dist.is_empty() {
                    return Err(bad(provider, format!("{name}: empty distribution")));
                }
                dist.sort_by(|a, b| b.1.total_cmp(&a.1));
                let confidence = match a.get("confidence") {
                    Some(v) => prob(provider, name, Some(v))?,
                    None => dist[0].1,
                };
                Answer::Choice {
                    distribution: dist,
                    confidence,
                }
            }
            Question::Noul { .. } => Answer::Noul {
                p: prob(provider, name, a.get("noul"))?,
            },
            Question::Score { legend, .. } => {
                let value = a
                    .get("score")
                    .and_then(Value::as_f64)
                    .ok_or_else(|| bad(provider, format!("{name}: no value")))?;
                #[allow(
                    clippy::cast_precision_loss,
                    reason = "a legend has a handful of entries"
                )]
                let max = legend.len().saturating_sub(1) as f64;
                if !(0.0..=max).contains(&value) {
                    return Err(bad(provider, format!("{name}: {value} outside the legend")));
                }
                let confidence = match a.get("confidence") {
                    Some(v) => prob(provider, name, Some(v))?,
                    None => 1.0,
                };
                Answer::Score { value, confidence }
            }
        };
        out.insert(name.clone(), answer);
    }
    Ok(Answers(out))
}

/// The hosted Jev API (through the Pilot relay by default).
pub struct HttpJev {
    pub remote: Remote,
    pub url: String,
    pub model: String,
    pub provider: String,
}

#[async_trait]
impl JevClient for HttpJev {
    async fn decide(&self, req: &DecideRequest, purpose: &str) -> Result<Answers, RemoteError> {
        for (name, q) in &req.questions {
            if let Question::Choice { options, .. } = q {
                if options.is_empty() || options.len() > MAX_CHOICE_OPTIONS {
                    return Err(bad(
                        &self.provider,
                        format!("{name}: {} options", options.len()),
                    ));
                }
            }
        }
        let body = json!({
            "model": self.model,
            "state": req.state,
            "questions": wire_questions(&req.questions),
        });
        let reply = self
            .remote
            .post_json(&self.provider, purpose, &self.url, &body)
            .await?;
        parse_answers(&self.provider, req, &reply.body)
    }

    fn provider(&self) -> &str {
        &self.provider
    }
}

/// Local mode's Jev: the phone's own parsers take what they can do without
/// a model (a timer, an alarm, music); everything else goes to the local
/// model. A choice among apps or actions (the two-stage tool routing) is
/// made by meaning, with a small embedding model on the phone, so the model
/// sees only the tools that can do it; by shared words while that model is
/// unavailable.
pub struct LocalJev {
    pub remote: Remote,
    /// OpenAI-compatible embeddings on this machine.
    pub embed_url: String,
    /// Options' embeddings: their descriptions rarely change.
    pub cache: std::sync::Mutex<std::collections::HashMap<String, Vec<f32>>>,
}

impl LocalJev {
    async fn embed(&self, purpose: &str, texts: &[String]) -> Result<Vec<Vec<f32>>, RemoteError> {
        let body = json!({"model": "e5-small", "input": texts});
        let reply = self.remote.post_json("local", purpose, &self.embed_url, &body).await?;
        let data = reply
            .body
            .get("data")
            .and_then(Value::as_array)
            .ok_or_else(|| bad("local", "no embeddings"))?;
        let mut out = vec![Vec::new(); texts.len()];
        for (i, d) in data.iter().enumerate() {
            let at = d.get("index").and_then(Value::as_u64).map_or(i, |x| usize::try_from(x).unwrap_or(i));
            let v: Vec<f32> = d
                .get("embedding")
                .and_then(Value::as_array)
                .map(|a| a.iter().filter_map(Value::as_f64).map(|x| x as f32).collect())
                .unwrap_or_default();
            if let Some(slot) = out.get_mut(at) {
                *slot = v;
            }
        }
        if out.iter().any(Vec::is_empty) {
            return Err(bad("local", "an embedding is missing"));
        }
        Ok(out)
    }

    /// [`rank`] by meaning: e5's query and passage forms, cosine similarity.
    async fn rank_by_meaning(
        &self,
        utterance: &str,
        options: &[String],
        descriptions: &[String],
    ) -> Result<Answer, RemoteError> {
        let passages: Vec<String> = options
            .iter()
            .enumerate()
            .map(|(i, o)| {
                let d = descriptions.get(i).map_or("", String::as_str);
                format!("passage: {} {d}", o.replace(['.', '_'], " ")).chars().take(1500).collect()
            })
            .collect();
        let missing: Vec<String> = {
            let cache = self.cache.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            passages.iter().filter(|p| !cache.contains_key(*p)).cloned().collect()
        };
        let mut texts = vec![format!("query: {utterance}")];
        texts.extend(missing.iter().cloned());
        let mut vectors = self.embed("decide", &texts).await?.into_iter();
        let query = vectors.next().unwrap_or_default();
        let mut cache = self.cache.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        for (p, v) in missing.into_iter().zip(vectors) {
            cache.insert(p, v);
        }
        let cosine = |a: &[f32], b: &[f32]| {
            let dot: f32 = a.iter().zip(b).map(|(x, y)| x * y).sum();
            let norm = |v: &[f32]| v.iter().map(|x| x * x).sum::<f32>().sqrt().max(f32::EPSILON);
            f64::from(dot / (norm(a) * norm(b)))
        };
        // e5's similarities sit close together: sharpened, and the words
        // the request shares with an option added (hybrid retrieval).
        let words = lexical(utterance, options, descriptions);
        let scores: Vec<f64> = passages
            .iter()
            .zip(words)
            .map(|(p, w)| cache.get(p).map_or(0.0, |v| cosine(&query, v)) / 0.02 + w)
            .collect();
        Ok(distribution(options, &scores))
    }
}

/// Words of `text`, lowercased, stemmed a little, without the commonest.
fn words(text: &str) -> Vec<String> {
    const STOP: &[&str] = &[
        "a", "an", "the", "to", "of", "in", "on", "for", "and", "or", "is", "it", "me", "my",
        "i", "you", "what", "can", "do", "does", "please", "with", "at", "this", "that", "be",
        "are", "how", "app",
    ];
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.len() > 1 && !STOP.contains(w))
        .map(|w| {
            let w = w.strip_suffix("ing").filter(|r| r.len() > 2).unwrap_or(w);
            let w = w.strip_suffix("es").filter(|r| r.len() > 2).unwrap_or(w);
            w.strip_suffix('s').filter(|r| r.len() > 2).unwrap_or(w).to_owned()
        })
        .collect()
}

/// The options most like `utterance`, most likely first, by [`lexical`].
fn rank(utterance: &str, options: &[String], descriptions: &[String]) -> Answer {
    distribution(options, &lexical(utterance, options, descriptions))
}

/// Each request word an option shares counts the more, the fewer options
/// have it.
fn lexical(utterance: &str, options: &[String], descriptions: &[String]) -> Vec<f64> {
    let asked = words(utterance);
    let texts: Vec<Vec<String>> = options
        .iter()
        .enumerate()
        .map(|(i, o)| words(&format!("{o} {}", descriptions.get(i).map_or("", String::as_str))))
        .collect();
    #[allow(clippy::cast_precision_loss, reason = "a handful of options")]
    let n = texts.len().max(1) as f64;
    texts
        .iter()
        .map(|t| {
            asked
                .iter()
                .filter(|w| t.contains(w))
                .map(|w| {
                    #[allow(clippy::cast_precision_loss, reason = "a handful of options")]
                    let with = texts.iter().filter(|x| x.contains(w)).count() as f64;
                    (n / with).ln() + 1.0
                })
                .sum()
        })
        .collect()
}

/// Options most likely first, from scores (softmax).
fn distribution(options: &[String], scores: &[f64]) -> Answer {
    let top = scores.iter().copied().fold(f64::MIN, f64::max);
    let total: f64 = scores.iter().map(|s| (s - top).exp()).sum();
    let mut distribution: Vec<(String, f64)> = options
        .iter()
        .cloned()
        .zip(scores.iter().map(|s| (s - top).exp() / total))
        .collect();
    distribution.sort_by(|a, b| b.1.total_cmp(&a.1));
    let confidence = distribution.first().map_or(0.0, |d| d.1);
    Answer::Choice {
        distribution,
        confidence,
    }
}

/// Facts that change: the web, before the model answers.
fn needs_web(utterance: &str) -> bool {
    const WORDS: &[&str] = &[
        "news", "latest", "today", "tonight", "current", "price", "prices", "cost", "score",
        "scores", "result", "results", "won", "match", "release", "version", "stock", "election",
        "recent", "yesterday",
    ];
    const PHRASES: &[&str] = &["who is", "opening hours", "this week", "right now"];
    let lower = utterance.to_lowercase();
    !lower.contains("weather")
        && (lower.split(|c: char| !c.is_alphanumeric()).any(|w| WORDS.contains(&w))
            || PHRASES.iter().any(|p| lower.contains(p)))
}

#[async_trait]
impl JevClient for LocalJev {
    async fn decide(&self, req: &DecideRequest, purpose: &str) -> Result<Answers, RemoteError> {
        if purpose != "decide" && purpose != "decide-action" {
            return Err(RemoteError::Offline);
        }
        let utterance = req.state.get("utterance").and_then(Value::as_str).unwrap_or_default();
        let parsed = crate::intents::local_intent(utterance).map(|(intent, _)| intent);
        let (intent, confidence, generation) = match parsed {
            Some(intent) => (intent, 1.0, 0.0),
            None => ("open_ended", 0.5, 1.0),
        };
        let mut out = BTreeMap::new();
        for (name, q) in &req.questions {
            let answer = match (name.as_str(), q) {
                ("intent", _) => Answer::Choice {
                    distribution: vec![(intent.to_owned(), confidence)],
                    confidence,
                },
                ("needs_generation", _) => Answer::Noul { p: generation },
                (_, Question::Choice {
                    options,
                    descriptions,
                    ..
                }) => match self.rank_by_meaning(utterance, options, descriptions).await {
                    Ok(a) => a,
                    Err(e) => {
                        log::warn!("local embeddings: {e}; ranking by words");
                        rank(utterance, options, descriptions)
                    }
                },
                ("needs_web", _) => Answer::Noul {
                    p: if needs_web(utterance) { 0.9 } else { 0.0 },
                },
                (_, Question::Noul { .. }) => Answer::Noul { p: 0.0 },
                (_, Question::Score { .. }) => Answer::Score {
                    value: 0.0,
                    confidence: 1.0,
                },
            };
            out.insert(name.clone(), answer);
        }
        Ok(Answers(out))
    }

    fn provider(&self) -> &str {
        "local"
    }
}

/// A label the scorer model can answer with, and its token id in that
/// model's tokenizer (configuration, since it depends on the model).
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct LabelToken {
    pub text: String,
    pub token_id: u32,
}

/// Listed options (label, text) and the label tokens to score.
type Labelled = (Vec<(String, String)>, Vec<u32>);

/// The Lighthouse scorer: SGLang `/v1/score` over an open model.
///
/// Each question becomes one prompt that lists the options with labels
/// ("A. alarm", "B. timer", ...) and ends in "Answer:". SGLang returns the
/// softmax restricted to the label tokens, which is the distribution.
/// Noul uses the yes and no tokens; Score labels the legend and reports
/// the probability-weighted position.
pub struct ScoreJev {
    pub remote: Remote,
    pub url: String,
    pub model: String,
    pub provider: String,
    pub labels: Vec<LabelToken>,
    pub yes: LabelToken,
    pub no: LabelToken,
}

impl ScoreJev {
    fn prompt(state: &Value, criteria: &str, listed: &[(String, String)]) -> String {
        let mut p =
            format!("You answer with a single label.\nState: {state}\nQuestion: {criteria}\n");
        if !listed.is_empty() {
            p.push_str("Options:\n");
            for (label, text) in listed {
                let _ = writeln!(p, "{label}. {text}");
            }
        }
        p
    }

    async fn score(
        &self,
        purpose: &str,
        query: String,
        tokens: Vec<u32>,
    ) -> Result<Vec<f64>, RemoteError> {
        let body = json!({
            "model": self.model,
            "query": query,
            "items": ["Answer:"],
            "label_token_ids": tokens,
            "apply_softmax": true,
            "item_first": false,
        });
        let reply = self
            .remote
            .post_json(&self.provider, purpose, &self.url, &body)
            .await?;
        let row = reply
            .body
            .get("scores")
            .and_then(|s| s.get(0))
            .and_then(Value::as_array)
            .ok_or_else(|| bad(&self.provider, "no scores[0]"))?;
        let probs: Vec<f64> = row
            .iter()
            .map(|v| prob(&self.provider, "score", Some(v)))
            .collect::<Result<_, _>>()?;
        if probs.len() != tokens.len() {
            return Err(bad(&self.provider, "score count differs from labels"));
        }
        Ok(probs)
    }

    fn labelled(&self, items: &[String]) -> Result<Labelled, RemoteError> {
        if items.len() > self.labels.len() {
            return Err(bad(
                &self.provider,
                format!(
                    "{} options but only {} labels configured",
                    items.len(),
                    self.labels.len()
                ),
            ));
        }
        let listed = self
            .labels
            .iter()
            .zip(items)
            .map(|(l, t)| (l.text.clone(), t.clone()))
            .collect();
        let tokens = self
            .labels
            .iter()
            .take(items.len())
            .map(|l| l.token_id)
            .collect();
        Ok((listed, tokens))
    }
}

#[async_trait]
impl JevClient for ScoreJev {
    async fn decide(&self, req: &DecideRequest, purpose: &str) -> Result<Answers, RemoteError> {
        let mut calls = Vec::new();
        for (name, q) in &req.questions {
            let (query, tokens, kind) = match q {
                Question::Choice {
                    options, criteria, ..
                } => {
                    let (listed, tokens) = self.labelled(options)?;
                    (Self::prompt(&req.state, criteria, &listed), tokens, q)
                }
                Question::Noul { criteria, .. } => {
                    let listed = vec![
                        (self.yes.text.clone(), "yes".to_owned()),
                        (self.no.text.clone(), "no".to_owned()),
                    ];
                    (
                        Self::prompt(&req.state, criteria, &listed),
                        vec![self.yes.token_id, self.no.token_id],
                        q,
                    )
                }
                Question::Score { legend, criteria } => {
                    let (listed, tokens) = self.labelled(legend)?;
                    (Self::prompt(&req.state, criteria, &listed), tokens, q)
                }
            };
            calls.push(async move {
                let probs = self.score(purpose, query, tokens).await?;
                Ok::<_, RemoteError>((name.clone(), kind, probs))
            });
        }
        let results = futures_util::future::try_join_all(calls).await?;
        let mut out = BTreeMap::new();
        for (name, q, probs) in results {
            let answer = match q {
                Question::Choice { options, .. } => {
                    let mut dist: Vec<(String, f64)> =
                        options.iter().cloned().zip(probs.iter().copied()).collect();
                    dist.sort_by(|a, b| b.1.total_cmp(&a.1));
                    let confidence = dist.first().map_or(0.0, |d| d.1);
                    Answer::Choice {
                        distribution: dist,
                        confidence,
                    }
                }
                Question::Noul { .. } => Answer::Noul { p: probs[0] },
                Question::Score { .. } => {
                    #[allow(clippy::cast_precision_loss, reason = "legend positions are small")]
                    let value = probs.iter().enumerate().map(|(i, p)| i as f64 * p).sum();
                    let confidence = probs.iter().copied().fold(0.0, f64::max);
                    Answer::Score { value, confidence }
                }
            };
            out.insert(name, answer);
        }
        Ok(Answers(out))
    }

    fn provider(&self) -> &str {
        &self.provider
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req() -> DecideRequest {
        let mut q = BTreeMap::new();
        q.insert(
            "intent".into(),
            Question::Choice {
                options: vec!["timer".into(), "alarm".into(), "open_ended".into()],
                criteria: "c".into(),
                descriptions: Vec::new(),
            },
        );
        q.insert(
            "needs_generation".into(),
            Question::Noul {
                criteria: "c".into(),
                yes: String::new(),
                no: String::new(),
            },
        );
        q.insert(
            "ambiguity".into(),
            Question::Score {
                legend: vec!["clear".into(), "minor gaps".into(), "missing".into()],
                criteria: "c".into(),
            },
        );
        DecideRequest {
            state: json!({"utterance": "x"}),
            questions: q,
        }
    }

    #[test]
    fn request_uses_jevs_schema() {
        let v = wire_questions(&req().questions);
        assert_eq!(v["intent"]["type"], "choice");
        assert_eq!(v["intent"]["instructions"], "c");
        assert!(v["intent"]["criteria"]["alarm"].is_null());
        assert_eq!(v["intent"]["criteria"].as_object().unwrap().len(), 3);
        assert_eq!(v["needs_generation"]["type"], "noul");
        assert_eq!(v["needs_generation"]["instructions"], "c");
        assert_eq!(v["ambiguity"]["type"], "score");
        assert_eq!(v["ambiguity"]["criteria"][2], "missing");
    }

    #[test]
    fn parses_a_live_reply() {
        // jev-1.13.0's reply to section 5.1's questions, 2026-10-03, with
        // the intent options cut to the three asked here.
        let body = json!({"model": "jev-1.13.0", "answers": {
            "intent": {"type": "choice", "choice": "timer", "confidence": 1.0,
                       "probabilities": {"timer": 1.0, "alarm": 0.0, "open_ended": 0.0}},
            "needs_generation": {"type": "noul", "noul": 0.63},
            "ambiguity": {"type": "score", "score": 1.13, "confidence": 0.11,
                          "legend": {"0": "clear", "1": "minor gaps", "2": "missing"},
                          "probabilities": {"0": 0.23, "1": 0.41, "2": 0.36}}
        }, "usage": {"input_tokens": 490, "output_tokens": 150}});
        let a = parse_answers("jev", &req(), &body).unwrap();
        assert_eq!(a.get("intent").unwrap().top(), Some("timer"));
        assert_eq!(a.get("needs_generation"), Some(&Answer::Noul { p: 0.63 }));
        match a.get("ambiguity").unwrap() {
            Answer::Score { value, confidence } => {
                assert!((value - 1.13).abs() < 1e-9);
                assert!((confidence - 0.11).abs() < 1e-9);
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn rejects_untyped_answers() {
        let ok =
            json!({"answers": {"needs_generation": {"noul": 0.1}, "ambiguity": {"score": 0.0}}});
        let mut bad_option = ok.clone();
        bad_option["answers"]["intent"] = json!({"probabilities": {"launch_missiles": 1.0}});
        assert!(parse_answers("jev", &req(), &bad_option).is_err());
        let mut bad_prob = ok.clone();
        bad_prob["answers"]["intent"] = json!({"probabilities": {"timer": 1.5}});
        assert!(parse_answers("jev", &req(), &bad_prob).is_err());
        let mut bad_score = ok.clone();
        bad_score["answers"]["intent"] = json!({"probabilities": {"timer": 1.0}});
        bad_score["answers"]["ambiguity"] = json!({"score": 7.0});
        assert!(parse_answers("jev", &req(), &bad_score).is_err());
        assert!(parse_answers("jev", &req(), &ok).is_err(), "missing intent");
        let bare = json!({"intent": {"probabilities": {"timer": 1.0}}});
        assert!(
            parse_answers("jev", &req(), &bare).is_err(),
            "no answers object"
        );
    }
}
