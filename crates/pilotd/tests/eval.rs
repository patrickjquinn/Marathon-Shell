// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Pilot's evaluation suite: realistic requests with checkable outcomes,
//! run against the real models (Jev and Qwen on Groq) with the phone's
//! apps replaced by recording fakes. What is scored is the whole turn:
//! what the apps were asked to do, which tools the model called, and the
//! answer (by rules, and by a judge model for the rubric items).
//!
//! Costs API calls, so it runs only when asked:
//!
//! ```text
//! PILOT_EVAL=1 cargo test -p shoal-pilotd --test eval -- --nocapture
//! PILOT_EVAL=1 PILOT_EVAL_ONLY=weather,memory cargo test ...   # some categories
//! PILOT_EVAL=1 PILOT_EVAL_ID=web-injection cargo test ...      # one task
//! ```
//!
//! Rubric items are not graded here by default: they go to
//! `target/pilot-eval/judge-<stamp>.json` for a judge agent, whose verdicts
//! (`{"<key>": {"pass", "reason"}}`) `tests/eval/merge-verdicts.py` applies
//! to the run. `PILOT_EVAL_JUDGE=groq` grades them here with the model
//! instead. The printed summary counts only the rule checks until then.
//!
//! Keys come from `~/.config/shipwright/pilot-keys.env` (as the relay's live
//! test reads them). Tasks are in `tests/eval/tasks.json`; web results are
//! fixed per task (`web`), so a run is repeatable apart from the models
//! and the live weather. Each run is written to `target/pilot-eval/` and
//! compared with the previous one.

mod common;

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use common::{FakeHttp, Log, Reply, Seen};
use pilotd::pipeline::{Card, TurnResult};
use serde::Deserialize;
use serde_json::{json, Value};

const JEV_URL: &str = "https://api.typesafe.ai/v1/systemone";
const GROQ_URL: &str = "https://api.groq.com/openai/v1/chat/completions";
const JUDGE_MODEL: &str = "qwen/qwen3.8-27b";

#[derive(Debug, Deserialize)]
struct Task {
    id: String,
    category: String,
    turns: Vec<Turn>,
    /// Canned results for any `web.search` in this task.
    #[serde(default)]
    web: Vec<Value>,
    /// Facts the person told Pilot to remember before the task.
    #[serde(default)]
    memories: Vec<String>,
    /// Earlier conversations, kept on the phone: [question, answer] pairs.
    #[serde(default)]
    history: Vec<(String, String)>,
}

#[derive(Debug, Deserialize)]
struct Turn {
    say: String,
    #[serde(default)]
    spoken: bool,
    /// Answer a confirmation card yes (true) or no (false); absent: leave it.
    #[serde(default)]
    approve: Option<bool>,
    #[serde(default)]
    expect: Expect,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
struct Expect {
    /// Each must be a substring of something the fake apps were asked to do.
    actions: Vec<String>,
    /// None may be.
    no_actions: Vec<String>,
    /// No app action at all.
    no_action: bool,
    /// Each must have been called by the model.
    tools: Vec<String>,
    /// None may have been.
    no_tools: Vec<String>,
    /// The answer contains at least one of these (case-insensitive).
    answer_any: Vec<String>,
    /// The answer contains none of these.
    answer_none: Vec<String>,
    /// The kind of the first card ("response", "timer", "confirm", ...).
    card: Option<String>,
    /// Graded by the judge model.
    judge: Option<String>,
    /// After the turn, a remembered fact contains each of these.
    remembered: Vec<String>,
    /// And none contains any of these.
    not_remembered: Vec<String>,
}

#[derive(Default)]
struct Upstream {
    /// Tool calls the model made, in order: (name, arguments).
    tool_calls: Vec<(String, String)>,
    llm_calls: u32,
    jev_calls: u32,
    tokens: u64,
    /// Per model call: the tools offered, and what came back when no words
    /// and no tool call did.
    notes: Vec<String>,
}

fn keys() -> Option<(String, String)> {
    let mut jev = std::env::var("PILOT_RELAY_JEV_KEY").ok();
    let mut groq = std::env::var("PILOT_RELAY_GROQ_KEY").ok();
    if let Some(home) = std::env::var_os("HOME") {
        let file = std::path::Path::new(&home).join(".config/shipwright/pilot-keys.env");
        if let Ok(text) = std::fs::read_to_string(file) {
            for line in text.lines() {
                if let Some((k, v)) = line.split_once('=') {
                    let v = v.trim().trim_matches('"').to_owned();
                    match k.trim() {
                        "PILOT_RELAY_JEV_KEY" if jev.is_none() => jev = Some(v),
                        "PILOT_RELAY_GROQ_KEY" if groq.is_none() => groq = Some(v),
                        _ => {}
                    }
                }
            }
        }
    }
    Some((jev?, groq?))
}

async fn post(url: &str, key: &str, body: &Value) -> (u16, Value) {
    let client = pilotd::remote::http_client().unwrap();
    for attempt in 0..4 {
        let r = client
            .post(url)
            .bearer_auth(key)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(body.to_string())
            .timeout(Duration::from_secs(60))
            .send()
            .await;
        match r {
            Ok(resp) => {
                let status = resp.status().as_u16();
                // Rate limited: wait and try again, as the relay's quota
                // would not.
                if status == 429 && attempt < 3 {
                    tokio::time::sleep(Duration::from_secs(4 << attempt)).await;
                    continue;
                }
                let bytes = resp.bytes().await.unwrap_or_default();
                let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
                return (status, v);
            }
            Err(e) if attempt < 3 => {
                eprintln!("eval: {url}: {e}; again");
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
            Err(e) => return (502, json!({"error": e.to_string()})),
        }
    }
    (502, Value::Null)
}

/// The relay's place: forwards to the real upstreams, records what the
/// model did, answers web searches from the task's fixtures.
fn relay(
    keys: (String, String),
    web: Arc<Mutex<Vec<Value>>>,
    up: Arc<Mutex<Upstream>>,
) -> impl Fn(&Seen, usize) -> Reply + Send + Sync + 'static {
    move |req, _| {
        let rt = tokio::runtime::Handle::current();
        match req.path.as_str() {
            "/v1/jev" => {
                up.lock().unwrap().jev_calls += 1;
                let (s, v) =
                    tokio::task::block_in_place(|| rt.block_on(post(JEV_URL, &keys.0, &req.body)));
                Reply {
                    status: s,
                    ..Reply::ok(v)
                }
            }
            "/v1/llm/chat/completions" => {
                let mut body = req.body.clone();
                if let Some(o) = body.as_object_mut() {
                    o.remove("store");
                    o.remove("user");
                }
                let (s, v) =
                    tokio::task::block_in_place(|| rt.block_on(post(GROQ_URL, &keys.1, &body)));
                let mut u = up.lock().unwrap();
                u.llm_calls += 1;
                let offered: Vec<&str> = body["tools"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|t| t["function"]["name"].as_str())
                    .collect();
                let choice = &v["choices"][0];
                let empty = choice["message"]["content"]
                    .as_str()
                    .is_none_or(|c| c.trim().is_empty())
                    && choice["message"]["tool_calls"].is_null();
                let n = u.llm_calls;
                u.notes.push(format!(
                    "call {}: offered [{}], effort {}{}",
                    n,
                    offered.join(", "),
                    body["reasoning_effort"].as_str().unwrap_or("-"),
                    if let Some(c) = choice["message"]["content"].as_str().filter(|c| c
                        .chars()
                        .count()
                        < 300
                        && choice["message"]["tool_calls"].is_null())
                    {
                        format!("; reply {c:?}")
                    } else if empty {
                        format!(
                            "; EMPTY reply (finish {}, status {s}, {} completion tokens)",
                            choice["finish_reason"], v["usage"]["completion_tokens"]
                        )
                    } else {
                        String::new()
                    }
                ));
                u.tokens += v["usage"]["total_tokens"].as_u64().unwrap_or(0);
                for c in v["choices"][0]["message"]["tool_calls"]
                    .as_array()
                    .into_iter()
                    .flatten()
                {
                    u.tool_calls.push((
                        c["function"]["name"].as_str().unwrap_or("").to_owned(),
                        c["function"]["arguments"].as_str().unwrap_or("").to_owned(),
                    ));
                }
                let status = if s == 400 && v["error"]["code"].as_str() == Some("tool_use_failed") {
                    422
                } else {
                    s
                };
                Reply {
                    status,
                    ..Reply::us(v)
                }
            }
            "/v1/search" => {
                // Searches pilotd runs itself (before the model) count as
                // the tool too.
                up.lock().unwrap().tool_calls.push((
                    "web.search".into(),
                    req.body["query"].as_str().unwrap_or("").to_owned(),
                ));
                Reply::ok(json!({"items": web.lock().unwrap().clone()}))
            }
            "/v1/token" => Reply::ok(json!({"token": "eval", "expires_in": 3600})),
            _ => Reply {
                status: 404,
                ..Reply::ok(json!({}))
            },
        }
    }
}

fn eval_config(base: &str) -> pilotd::config::Config {
    pilotd::config::Config::parse(&format!(
        r#"
        timeout_secs = 60
        token_exchange_url = "{base}/v1/token"
        web_search_url = "{base}/v1/search"
        [privacy]
        source = "none"
        [backends.standard.jev]
        kind = "jev"
        url = "{base}/v1/jev"
        [backends.standard.llm]
        url = "{base}/v1/llm/chat/completions"
        "#
    ))
    .unwrap()
}

/// "reminder x @1791730208" with the time as the phone shows it, for
/// the judge (and for reading).
fn readable_times(action: &str) -> String {
    match action.rsplit_once(" @") {
        Some((head, epoch)) => match epoch.parse::<i64>() {
            Ok(e) => {
                let t = pilotd::localtime::at(e);
                format!("{head} @{} {}", t.long_date(), t.hhmm())
            }
            Err(_) => action.to_owned(),
        },
        None => action.to_owned(),
    }
}

/// The text a person reads in a turn's cards.
fn shown(r: &TurnResult) -> String {
    let v = serde_json::to_value(&r.cards).unwrap_or_default();
    let mut out = String::new();
    for c in v.as_array().into_iter().flatten() {
        for k in ["text", "title", "detail"] {
            if let Some(s) = c[k].as_str() {
                out.push_str(s);
                out.push('\n');
            }
        }
    }
    out
}

fn card_kind(c: &Card) -> String {
    serde_json::to_value(c).unwrap_or_default()["kind"]
        .as_str()
        .unwrap_or("")
        .to_owned()
}

/// The judge: one call, temperature 0, a yes or no with a reason.
async fn judge(key: &str, rubric: &str, transcript: &str) -> (bool, String) {
    let now = pilotd::localtime::now();
    let today = format!("{}, {}", now.long_date(), now.hhmm());
    let prompt = format!(
        "You grade a phone assistant's turn strictly. Today is {today}. Rubric: {rubric}\n\n\
         The turn (what the person said, what the assistant did and showed):\n{transcript}\n\n\
         Answer with JSON only: {{\"pass\": true|false, \"reason\": \"one sentence\"}}."
    );
    let (_, v) = post(
        GROQ_URL,
        key,
        // A little reasoning: without it the judge's verdicts flipped on
        // the same answer ("the 17th is not next Saturday").
        &json!({"model": JUDGE_MODEL, "temperature": 0.6, "reasoning_effort": "low",
                "reasoning_format": "hidden", "max_completion_tokens": 2000,
                "messages": [{"role": "user", "content": prompt}]}),
    )
    .await;
    let text = v["choices"][0]["message"]["content"]
        .as_str()
        .unwrap_or("")
        .to_owned();
    let start = text.find('{').unwrap_or(0);
    let end = text.rfind('}').map_or(text.len(), |e| e + 1);
    match serde_json::from_str::<Value>(&text[start..end]) {
        Ok(j) => (
            j["pass"].as_bool().unwrap_or(false),
            j["reason"].as_str().unwrap_or("").to_owned(),
        ),
        Err(_) => (false, format!("judge said: {text}")),
    }
}

struct Outcome {
    id: String,
    category: String,
    pass: bool,
    failures: Vec<String>,
    ms: Vec<u64>,
    llm_calls: u32,
    tool_calls: usize,
    tokens: u64,
    transcript: String,
    /// Rubric items left for the judge agent: (turn, rubric, transcript so far).
    judgments: Vec<(usize, String, String)>,
}

/// Whether the rubric items go to the Groq judge (`PILOT_EVAL_JUDGE=groq`)
/// or into the run's file, for a judge agent (the default: no API use
/// for grading).
fn groq_judge() -> bool {
    std::env::var("PILOT_EVAL_JUDGE").is_ok_and(|v| v == "groq")
}

#[allow(clippy::too_many_lines, reason = "one task, start to finish")]
async fn run_task(task: &Task, keys: &(String, String)) -> Outcome {
    let web = Arc::new(Mutex::new(task.web.clone()));
    let up = Arc::new(Mutex::new(Upstream::default()));
    let srv = FakeHttp::start(relay(keys.clone(), web, up.clone())).await;
    let log = Arc::new(Log::default());
    let d = pilotd::daemon::build(pilotd::daemon::Options {
        config: eval_config(&srv.base),
        data_dir: None,
        session: None,
        system: None,
        adapters: Some(common::fake_adapters(&log)),
        credential: Some(pilotd::remote::Credential::None),
        licence: None,
        now: pilotd::localtime::now,
    })
    .unwrap();
    {
        let mut live = d.live.lock().unwrap();
        live.consent.voice_cloud = true;
    }
    for m in &task.memories {
        let _ = d.store.remember(m);
    }
    for (q, a) in &task.history {
        let _ = d.store.log_exchange(q, a);
    }
    let mut failures = Vec::new();
    let mut judgments = Vec::new();
    let mut ms = Vec::new();
    let mut transcript = String::new();
    if !task.web.is_empty() {
        let _ = writeln!(
            transcript,
            "(Web search results available to the assistant: {})",
            Value::Array(task.web.clone())
        );
    }
    for (n, turn) in task.turns.iter().enumerate() {
        let actions_before = log.all().len();
        let tools_before = up.lock().unwrap().tool_calls.len();
        let started = Instant::now();
        let mut r = d.pipeline.ask(&turn.say, turn.spoken).await;
        let mut said = shown(&r);
        let mut kinds: Vec<String> = r.cards.iter().map(card_kind).collect();
        if let (Some(yes), Some(Card::Confirm { id, .. })) = (
            turn.approve,
            r.cards.iter().find(|c| matches!(c, Card::Confirm { .. })),
        ) {
            let id = id.clone();
            let after = d.pipeline.confirm(&id, yes).await;
            let _ = writeln!(said, "[person answers {}]", if yes { "yes" } else { "no" });
            said.push_str(&shown(&after));
            kinds.extend(after.cards.iter().map(card_kind));
            r = after;
        }
        let _ = &r;
        ms.push(u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX));
        let actions: Vec<String> = log.all()[actions_before..].to_vec();
        let actions: Vec<String> = actions
            .into_iter()
            .filter(|a| !a.starts_with("say ") && !a.starts_with("notify "))
            .map(|a| readable_times(&a))
            .collect();
        let tools: Vec<(String, String)> = up.lock().unwrap().tool_calls[tools_before..].to_vec();
        let notes: Vec<String> = std::mem::take(&mut up.lock().unwrap().notes);
        let _ = writeln!(
            transcript,
            "Person{}: {}\nTools called: {}\nApps asked to: {}\nAssistant shows [{}]: {}",
            if turn.spoken { " (spoken)" } else { "" },
            turn.say,
            tools
                .iter()
                .map(|(t, a)| format!("{t}({a})"))
                .collect::<Vec<_>>()
                .join("; "),
            actions.join("; "),
            kinds.join(", "),
            said.trim()
        );
        // Diagnostics for reading the run, kept from the judge (it marked
        // down the raw follow-up line the person never sees).
        let mut diag = String::new();
        for n in &notes {
            let _ = writeln!(diag, "  ({n})");
        }
        let e = &turn.expect;
        let tag = format!("turn {}", n + 1);
        let low = said.to_lowercase();
        let tool_name = |t: &str| t.replace("__", "/").replace('_', ".");
        for want in &e.actions {
            if !actions.iter().any(|a| a.contains(want.as_str())) {
                failures.push(format!("{tag}: no action {want:?} (got {actions:?})"));
            }
        }
        for not in &e.no_actions {
            if actions.iter().any(|a| a.contains(not.as_str())) {
                failures.push(format!("{tag}: unwanted action {not:?}"));
            }
        }
        if e.no_action && !actions.is_empty() {
            failures.push(format!("{tag}: acted: {actions:?}"));
        }
        for want in &e.tools {
            if !tools
                .iter()
                .any(|(t, _)| tool_name(t) == *want || t == want)
            {
                failures.push(format!(
                    "{tag}: tool {want} not called (called {:?})",
                    tools.iter().map(|t| &t.0).collect::<Vec<_>>()
                ));
            }
        }
        for not in &e.no_tools {
            if tools.iter().any(|(t, _)| tool_name(t) == *not || t == not) {
                failures.push(format!("{tag}: tool {not} called"));
            }
        }
        if !e.answer_any.is_empty() && !e.answer_any.iter().any(|w| low.contains(&w.to_lowercase()))
        {
            failures.push(format!(
                "{tag}: answer has none of {:?}: {}",
                e.answer_any,
                said.trim()
            ));
        }
        for not in &e.answer_none {
            if low.contains(&not.to_lowercase()) {
                failures.push(format!("{tag}: answer has {not:?}: {}", said.trim()));
            }
        }
        if let Some(k) = &e.card {
            if kinds.first() != Some(k) {
                failures.push(format!("{tag}: first card {:?}, wanted {k}", kinds.first()));
            }
        }
        let facts: Vec<String> = d
            .store
            .memories()
            .unwrap_or_default()
            .into_iter()
            .map(|m| m.fact.to_lowercase())
            .collect();
        for want in &e.remembered {
            if !facts.iter().any(|f| f.contains(&want.to_lowercase())) {
                failures.push(format!(
                    "{tag}: nothing remembered with {want:?} (have {facts:?})"
                ));
            }
        }
        for not in &e.not_remembered {
            if facts.iter().any(|f| f.contains(&not.to_lowercase())) {
                failures.push(format!("{tag}: still remembers {not:?} (have {facts:?})"));
            }
        }
        if let Some(rubric) = &e.judge {
            if groq_judge() {
                let (ok, why) = judge(&keys.1, rubric, &transcript).await;
                if !ok {
                    failures.push(format!("{tag}: judge: {why}"));
                }
            } else {
                judgments.push((n + 1, rubric.clone(), transcript.clone()));
            }
        }
        transcript.push_str(&diag);
    }
    let u = up.lock().unwrap();
    Outcome {
        id: task.id.clone(),
        category: task.category.clone(),
        pass: failures.is_empty(),
        failures,
        ms,
        llm_calls: u.llm_calls,
        tool_calls: u.tool_calls.len(),
        tokens: u.tokens,
        transcript,
        judgments,
    }
}

fn percentile(v: &mut [u64], p: f64) -> u64 {
    if v.is_empty() {
        return 0;
    }
    v.sort_unstable();
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        clippy::cast_precision_loss,
        reason = "an index into a short list"
    )]
    let i = ((v.len() - 1) as f64 * p).round() as usize;
    v[i]
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[allow(
    clippy::cast_precision_loss,
    clippy::too_many_lines,
    reason = "averages over a few hundred turns; one run, start to report"
)]
async fn eval() {
    if std::env::var_os("PILOT_EVAL").is_none() {
        return;
    }
    let keys = keys().expect("Jev and Groq keys (pilot-keys.env)");
    let tasks: Vec<Task> = serde_json::from_str(include_str!("eval/tasks.json")).unwrap();
    let only: Vec<String> = std::env::var("PILOT_EVAL_ONLY")
        .map(|s| s.split(',').map(str::to_owned).collect())
        .unwrap_or_default();
    let id: Option<String> = std::env::var("PILOT_EVAL_ID").ok();
    let tasks: Vec<&Task> = tasks
        .iter()
        .filter(|t| only.is_empty() || only.contains(&t.category))
        .filter(|t| id.as_ref().is_none_or(|i| t.id.starts_with(i.as_str())))
        .collect();
    let mut outcomes = Vec::new();
    // PILOT_EVAL_REPEAT=n runs each task n times: the models sample, so a
    // change is judged by pass rates, not one run.
    let repeat: usize = std::env::var("PILOT_EVAL_REPEAT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1)
        .max(1);
    let runs: Vec<&Task> = tasks
        .iter()
        .flat_map(|t| std::iter::repeat_n(*t, repeat))
        .collect();
    for t in runs {
        let o = run_task(t, &keys).await;
        println!(
            "{} {:<28} {:>6} ms {}",
            if o.pass { "pass" } else { "FAIL" },
            o.id,
            o.ms.iter().sum::<u64>(),
            o.failures.join(" | ")
        );
        if !o.pass && std::env::var_os("PILOT_EVAL_VERBOSE").is_some() {
            println!("{}", o.transcript);
        }
        outcomes.push(o);
    }
    if repeat > 1 {
        let mut rate: BTreeMap<&str, (u32, u32)> = BTreeMap::new();
        for o in &outcomes {
            let e = rate.entry(o.id.as_str()).or_default();
            e.1 += 1;
            e.0 += u32::from(o.pass);
        }
        println!("\nper task (passes of {repeat}):");
        for (id, (p, n)) in &rate {
            if p < n {
                println!("  {id:<28} {p}/{n}");
            }
        }
    }
    // Summary by category.
    let mut by: BTreeMap<&str, (u32, u32)> = BTreeMap::new();
    for o in &outcomes {
        let e = by.entry(o.category.as_str()).or_default();
        e.1 += 1;
        if o.pass {
            e.0 += 1;
        }
    }
    let mut all_ms: Vec<u64> = outcomes.iter().flat_map(|o| o.ms.clone()).collect();
    let passed = outcomes.iter().filter(|o| o.pass).count();
    println!("\n{:<14} pass", "category");
    for (c, (p, n)) in &by {
        println!("{c:<14} {p}/{n}");
    }
    let turns = all_ms.len().max(1);
    println!(
        "\n{passed}/{} tasks passed; turn latency p50 {} ms, p90 {} ms; {:.1} model calls and {:.1} tool calls a turn; {} tokens",
        outcomes.len(),
        percentile(&mut all_ms, 0.5),
        percentile(&mut all_ms, 0.9),
        f64::from(outcomes.iter().map(|o| o.llm_calls).sum::<u32>()) / turns as f64,
        outcomes.iter().map(|o| o.tool_calls).sum::<usize>() as f64 / turns as f64,
        outcomes.iter().map(|o| o.tokens).sum::<u64>()
    );
    // Kept, and compared with the last run.
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../target/pilot-eval");
    let _ = std::fs::create_dir_all(&dir);
    let mut runs: Vec<_> = std::fs::read_dir(&dir)
        .map(|d| d.flatten().map(|e| e.path()).collect())
        .unwrap_or_default();
    runs.sort();
    let previous: BTreeMap<String, bool> = runs
        .last()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .map(|v| {
            v["tasks"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|t| {
                    (
                        t["id"].as_str().unwrap_or("").to_owned(),
                        t["pass"].as_bool().unwrap_or(false),
                    )
                })
                .collect()
        })
        .unwrap_or_default();
    for o in &outcomes {
        match previous.get(&o.id) {
            Some(true) if !o.pass => println!("REGRESSED {}", o.id),
            Some(false) if o.pass => println!("fixed     {}", o.id),
            _ => {}
        }
    }
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let record = json!({
        "at": stamp,
        "tasks": outcomes.iter().map(|o| json!({
            "id": o.id, "category": o.category, "pass": o.pass, "failures": o.failures,
            "ms": o.ms, "llm_calls": o.llm_calls, "tool_calls": o.tool_calls,
            "tokens": o.tokens, "transcript": o.transcript,
            "judgments": o.judgments.iter().map(|(t, r, x)| json!({"turn": t, "rubric": r, "transcript": x})).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
    });
    // The rubric items, for a judge agent: one file, keys "<run index>:<turn>".
    let pending: Vec<Value> = outcomes
        .iter()
        .enumerate()
        .flat_map(|(i, o)| {
            o.judgments.iter().map(move |(t, r, x)| {
                json!({"key": format!("{i}:{t}"), "task": o.id, "rubric": r, "transcript": x})
            })
        })
        .collect();
    if !pending.is_empty() {
        let now = pilotd::localtime::now();
        let path = dir.join(format!("judge-{stamp}.json"));
        let _ = std::fs::write(
            &path,
            serde_json::to_string_pretty(&json!({
                "today": format!("{}, {}", now.long_date(), now.hhmm()),
                "run": format!("run-{stamp}.json"),
                "items": pending,
            }))
            .unwrap(),
        );
        println!(
            "\n{} rubric item(s) for the judge agent: {} (then tests/eval/merge-verdicts.py)",
            pending.len(),
            path.display()
        );
    }
    let _ = std::fs::write(
        dir.join(format!("run-{stamp}.json")),
        serde_json::to_string_pretty(&record).unwrap(),
    );
}
