// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Fixtures: a fake HTTP server standing in for Jev, Groq (via the relay)
//! and the Lighthouse scorer, and recording fakes for the Sailfish
//! adapters. No real keys, no network.

#![allow(clippy::unwrap_used, clippy::let_underscore_must_use, reason = "tests")]
#![allow(dead_code, reason = "each test binary uses part of it")]

use std::fmt::Write as _;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use pilotd::adapters::{
    AdapterError, Adapters, Calendar, CalendarEvent, Clock, Contact, Contacts, DeviceToggles,
    Media, Notifier, Speech, Telephony, Toggle, VoiceControl,
};
use pilotd::intents::MediaAction;
use serde_json::Value;
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::TcpListener;

/// One request the fake server saw.
#[derive(Debug, Clone)]
pub struct Seen {
    pub path: String,
    pub auth: Option<String>,
    pub body: Value,
}

pub struct Reply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Value,
    pub delay: Duration,
}

impl Reply {
    pub fn ok(body: Value) -> Reply {
        Reply {
            status: 200,
            headers: Vec::new(),
            body,
            delay: Duration::ZERO,
        }
    }

    /// As the relay answers an LLM call: stamped with the region of its
    /// Groq upstream, `us`.
    pub fn us(body: Value) -> Reply {
        Reply::stamped(body, "us")
    }

    /// An LLM reply stamped with `region`.
    pub fn stamped(body: Value, region: &str) -> Reply {
        let mut r = Reply::ok(body);
        r.headers
            .push(("x-pilot-processing-region".into(), region.into()));
        r
    }
}

type Handler = Box<dyn Fn(&Seen, usize) -> Reply + Send + Sync>;

/// A minimal HTTP/1.1 server: one request per connection.
pub struct FakeHttp {
    pub base: String,
    pub seen: Arc<Mutex<Vec<Seen>>>,
}

impl FakeHttp {
    /// `handler(request, index_of_request_on_this_path)`.
    pub async fn start(
        handler: impl Fn(&Seen, usize) -> Reply + Send + Sync + 'static,
    ) -> FakeHttp {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen: Arc<Mutex<Vec<Seen>>> = Arc::default();
        let handler: Arc<Handler> = Arc::new(Box::new(handler));
        let seen2 = Arc::clone(&seen);
        tokio::spawn(async move {
            loop {
                let Ok((mut sock, _)) = listener.accept().await else {
                    return;
                };
                let handler = Arc::clone(&handler);
                let seen = Arc::clone(&seen2);
                tokio::spawn(async move {
                    let mut buf = Vec::new();
                    let mut tmp = [0u8; 4096];
                    let header_end = loop {
                        let n = sock.read(&mut tmp).await.unwrap_or(0);
                        if n == 0 {
                            return;
                        }
                        buf.extend_from_slice(&tmp[..n]);
                        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                            break i + 4;
                        }
                    };
                    let head = String::from_utf8_lossy(&buf[..header_end]).to_string();
                    let mut lines = head.lines();
                    let path = lines
                        .next()
                        .and_then(|l| l.split_whitespace().nth(1))
                        .unwrap_or("/")
                        .to_owned();
                    let mut len = 0;
                    let mut auth = None;
                    for l in lines {
                        if let Some((k, v)) = l.split_once(':') {
                            match k.trim().to_ascii_lowercase().as_str() {
                                "content-length" => len = v.trim().parse().unwrap_or(0),
                                "authorization" => auth = Some(v.trim().to_owned()),
                                _ => {}
                            }
                        }
                    }
                    while buf.len() < header_end + len {
                        let n = sock.read(&mut tmp).await.unwrap_or(0);
                        if n == 0 {
                            break;
                        }
                        buf.extend_from_slice(&tmp[..n]);
                    }
                    let body = serde_json::from_slice(&buf[header_end..]).unwrap_or(Value::Null);
                    let req = Seen {
                        path: path.clone(),
                        auth,
                        body,
                    };
                    let index = {
                        let mut s = seen.lock().unwrap();
                        let i = s.iter().filter(|x| x.path == path).count();
                        s.push(req.clone());
                        i
                    };
                    let reply = handler(&req, index);
                    tokio::time::sleep(reply.delay).await;
                    let body = serde_json::to_vec(&reply.body).unwrap();
                    let mut out = format!(
                        "HTTP/1.1 {} X\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n",
                        reply.status,
                        body.len()
                    );
                    for (k, v) in &reply.headers {
                        let _ = write!(out, "{k}: {v}\r\n");
                    }
                    out.push_str("\r\n");
                    let _ = sock.write_all(out.as_bytes()).await;
                    let _ = sock.write_all(&body).await;
                    let _ = sock.shutdown().await;
                });
            }
        });
        FakeHttp { base, seen }
    }

    pub fn seen(&self, path: &str) -> Vec<Seen> {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|s| s.path == path)
            .cloned()
            .collect()
    }
}

/// A Jev reply (its published schema) with the given intent probabilities
/// and scalars.
pub fn jev_reply(intent: &[(&str, f64)], needs_generation: f64, ambiguity: f64) -> Value {
    let dist: serde_json::Map<String, Value> = intent
        .iter()
        .map(|(k, v)| ((*k).to_owned(), Value::from(*v)))
        .collect();
    serde_json::json!({"answers": {
        "intent": {"probabilities": dist, "confidence": intent[0].1},
        "needs_generation": {"noul": needs_generation},
        "needs_web": {"noul": 0.1},
        "ambiguity": {"score": ambiguity, "confidence": 0.9}
    }})
}

pub fn chat_text(text: &str) -> Value {
    serde_json::json!({"choices": [{"finish_reason": "stop",
        "message": {"role": "assistant", "content": text}}]})
}

pub fn chat_tool(name: &str, args: &str) -> Value {
    serde_json::json!({"choices": [{"finish_reason": "tool_calls",
        "message": {"role": "assistant", "content": null,
            "tool_calls": [{"id": "call_1", "type": "function",
                "function": {"name": name, "arguments": args}}]}}]})
}

/// What the fake adapters were asked to do.
#[derive(Debug, Default)]
pub struct Log(pub Mutex<Vec<String>>);

impl Log {
    pub fn push(&self, s: String) {
        self.0.lock().unwrap().push(s);
    }
    pub fn all(&self) -> Vec<String> {
        self.0.lock().unwrap().clone()
    }
}

pub struct Fake(pub Arc<Log>);

#[async_trait]
impl Clock for Fake {
    async fn set_timer(&self, seconds: u32, label: Option<&str>) -> Result<u32, AdapterError> {
        self.0.push(format!("timer {seconds} {label:?}"));
        // A cookie of its own for each timer (the log's length).
        Ok(10 + u32::try_from(self.0.all().len()).unwrap_or(0))
    }
    async fn set_alarm(&self, h: u32, m: u32, label: Option<&str>) -> Result<u32, AdapterError> {
        self.0.push(format!("alarm {h:02}:{m:02} {label:?}"));
        Ok(2)
    }
    async fn create_reminder(&self, title: &str, at: i64) -> Result<u32, AdapterError> {
        self.0.push(format!("reminder {title} @{at}"));
        Ok(3)
    }
    async fn cancel(&self, cookie: u32) -> Result<bool, AdapterError> {
        self.0.push(format!("cancel {cookie}"));
        Ok(true)
    }
}

#[async_trait]
impl Media for Fake {
    async fn control(&self, action: MediaAction) -> Result<String, AdapterError> {
        self.0.push(format!("media {}", action.as_str()));
        Ok("fake".into())
    }
}

impl Calendar for Fake {
    fn events(&self, from: i64, to: i64, _: usize) -> Result<Vec<CalendarEvent>, AdapterError> {
        self.0.push(format!("calendar {from}..{to}"));
        Ok(vec![CalendarEvent {
            title: "Standup".into(),
            start: from + 3600,
            end: from + 5400,
            all_day: false,
            location: None,
        }])
    }
}

pub struct FakeContacts;

impl Contacts for FakeContacts {
    fn names(&self) -> Vec<String> {
        vec!["Anna Virtanen".into()]
    }
    fn lookup(&self, q: &str, _: usize) -> Result<Vec<Contact>, AdapterError> {
        Ok(if "anna virtanen".contains(&q.to_lowercase()) {
            vec![Contact {
                name: "Anna Virtanen".into(),
                phones: vec!["+358 40 123 4567".into()],
                emails: vec![],
            }]
        } else {
            vec![]
        })
    }
}

#[async_trait]
impl pilotd::adapters::stock::StockApps for Fake {
    async fn compose_email(
        &self,
        to: &str,
        subject: &str,
        body: &str,
    ) -> Result<bool, AdapterError> {
        self.0.push(format!("email {to} | {subject} | {body}"));
        Ok(true)
    }
    async fn new_note(&self, text: &str) -> Result<(), AdapterError> {
        self.0.push(format!("note {text}"));
        Ok(())
    }
    async fn open_settings(&self, path: &str) -> Result<(), AdapterError> {
        self.0.push(format!("settings {path}"));
        Ok(())
    }
    async fn compose_sms(&self, number: &str, body: &str) -> Result<(), AdapterError> {
        self.0.push(format!("sms draft {number} {body}"));
        Ok(())
    }
}

#[async_trait]
impl Telephony for Fake {
    async fn dial(&self, number: &str) -> Result<(), AdapterError> {
        self.0.push(format!("dial {number}"));
        Ok(())
    }
    async fn send_sms(&self, to: &str, text: &str) -> Result<(), AdapterError> {
        self.0.push(format!("sms {to} {text}"));
        Ok(())
    }
}

#[async_trait]
impl DeviceToggles for Fake {
    async fn set(&self, what: Toggle, on: bool) -> Result<(), AdapterError> {
        self.0.push(format!("toggle {what:?} {on}"));
        Ok(())
    }
    async fn get(&self, what: Toggle) -> Result<bool, AdapterError> {
        self.0.push(format!("status {what:?}"));
        Ok(true)
    }
}

/// `pilot-voice` stand-in: hands out queued transcripts (`!message`: a
/// failure).
pub struct FakeVoice(pub Arc<Log>, pub Arc<Mutex<Vec<String>>>);

#[async_trait]
impl VoiceControl for FakeVoice {
    async fn listen(&self) -> Result<String, AdapterError> {
        self.0.push("voice listened".into());
        let mut q = self.1.lock().unwrap();
        if q.is_empty() {
            Err(AdapterError::Unavailable("voice".into()))
        } else {
            // "!message": pilot-voice fails with it.
            let next = q.remove(0);
            match next.strip_prefix('!') {
                Some(m) => Err(AdapterError::Failed(m.into())),
                None => Ok(next),
            }
        }
    }
    async fn stop(&self) -> Result<(), AdapterError> {
        self.0.push("voice stopped".into());
        Ok(())
    }
}

impl Speech for Fake {
    fn say(&self, text: &str) {
        self.0.push(format!("say {text}"));
    }
    fn stop(&self) {
        self.0.push("speech stopped".into());
    }
}

/// The home screen's notifications: logs `notify <id> <summary> | <body> | <hints>`
/// and `close <id>`; ids count from 1, a replaced id is kept.
#[async_trait]
impl Notifier for Fake {
    async fn show(
        &self,
        replaces: u32,
        summary: &str,
        body: &str,
        hints: &[(&str, String)],
    ) -> Result<u32, AdapterError> {
        let id = if replaces == 0 {
            1 + u32::try_from(
                self.0
                    .all()
                    .iter()
                    .filter(|l| l.starts_with("notify "))
                    .count(),
            )
            .unwrap()
        } else {
            replaces
        };
        let h: Vec<String> = hints.iter().map(|(k, v)| format!("{k}={v}")).collect();
        self.0
            .push(format!("notify {id} {summary} | {body} | {}", h.join(";")));
        Ok(id)
    }
    async fn close(&self, id: u32) -> Result<(), AdapterError> {
        self.0.push(format!("close {id}"));
        Ok(())
    }
}

pub fn fake_adapters(log: &Arc<Log>) -> Adapters {
    fake_adapters_hearing(log, Arc::default())
}

pub fn fake_adapters_hearing(log: &Arc<Log>, heard: Arc<Mutex<Vec<String>>>) -> Adapters {
    Adapters {
        clock: Box::new(Fake(Arc::clone(log))),
        media: Box::new(Fake(Arc::clone(log))),
        calendar: Box::new(Fake(Arc::clone(log))),
        contacts: Arc::new(FakeContacts),
        telephony: Box::new(Fake(Arc::clone(log))),
        toggles: Box::new(Fake(Arc::clone(log))),
        voice: Box::new(FakeVoice(Arc::clone(log), heard)),
        speech: Box::new(Fake(Arc::clone(log))),
        notifier: Box::new(Fake(Arc::clone(log))),
        stock: Box::new(Fake(Arc::clone(log))),
    }
}

/// A config pointing both backends at `base`.
pub fn config(base: &str) -> pilotd::config::Config {
    pilotd::config::Config::parse(&format!(
        r#"
        timeout_secs = 5
        [privacy]
        source = "none"
        [backends.standard.jev]
        kind = "jev"
        url = "{base}/v1/jev"
        [backends.standard.llm]
        url = "{base}/v1/llm/chat/completions"
        [backends.lighthouse.jev]
        kind = "score"
        url = "{base}/v1/score"
        model = "scorer"
        labels = [{{ text = "A", token_id = 1 }}, {{ text = "B", token_id = 2 }}, {{ text = "C", token_id = 3 }},
                  {{ text = "D", token_id = 4 }}, {{ text = "E", token_id = 5 }}, {{ text = "F", token_id = 6 }},
                  {{ text = "G", token_id = 7 }}, {{ text = "H", token_id = 8 }}, {{ text = "I", token_id = 9 }},
                  {{ text = "J", token_id = 10 }}, {{ text = "K", token_id = 11 }}, {{ text = "L", token_id = 12 }},
                  {{ text = "M", token_id = 13 }}, {{ text = "N", token_id = 14 }},
                  {{ text = "O", token_id = 15 }}, {{ text = "P", token_id = 16 }},
                  {{ text = "Q", token_id = 17 }}]
        yes = {{ text = "yes", token_id = 100 }}
        no = {{ text = "no", token_id = 101 }}
        [backends.lighthouse.llm]
        url = "{base}/lighthouse/chat/completions"
        provider = "lighthouse-llm"
        "#
    ))
    .unwrap()
}

/// A daemon wired to the fake server and fake adapters.
pub fn daemon(
    base: &str,
    log: &Arc<Log>,
    data_dir: Option<std::path::PathBuf>,
) -> pilotd::daemon::Daemon {
    pilotd::daemon::build(pilotd::daemon::Options {
        config: config(base),
        data_dir,
        session: None,
        system: None,
        adapters: Some(fake_adapters(log)),
        credential: Some(pilotd::remote::Credential::None),
        // Fixed: Friday 2 October 2026, 18:42:30 UTC.
        now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
    })
    .unwrap()
}
