// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Proactive triage (spec section 5.3). Opt-in: nothing here runs without
//! the `triage` consent, and nothing runs while the privacy switch is on.
//!
//! For each incoming notification, SMS or calendar change, one Jev request
//! (purpose `triage`) with three questions: Noul `worth_interrupting`,
//! Choice `bucket` (`act_now`, `today`, `later`, `ignore`) and Score `urgency`
//! (routine, time-sensitive, urgent). The title and body are redacted
//! first, like every other remote call; the app name and source are not
//! personal. Results are kept on the device (`triage` table, newest 200)
//! for the Pilot tab of the Events view, and nothing is spoken unless
//! `worth_interrupting >= 0.9` (`[triage] nudge_at`) and spoken nudges are
//! on.
//!
//! Two feeders produce [`Incoming`] events:
//!
//! - [`watch_notifications`]: a D-Bus monitor connection on the session
//!   bus that sees every `org.freedesktop.Notifications.Notify` call
//!   (Lipstick is the server on Sailfish; commhistoryd posts SMS and chat
//!   messages through it, with `x-nemo.messaging.*` categories).
//! - [`CalendarWatch`]: polls the calendar for the coming week and reports
//!   events added, moved or removed since the last poll.
//!
//! Cost is bounded: identical events within ten minutes are triaged once,
//! and at most `[triage] per_hour` requests go out in any hour.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Deserialize;
use serde_json::json;

use crate::adapters::{Adapters, CalendarEvent};
use crate::jev::{Answer, DecideRequest, Question};
use crate::localtime::LocalNow;
use crate::pipeline::Pipeline;
use crate::privacy::Offline;
use crate::settings::Settings;
use crate::store::{self, Store, TriageItem};

/// `[triage]` in pilotd.toml.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TriageConfig {
    /// Jev requests per rolling hour; events beyond it are not triaged.
    pub per_hour: u32,
    /// `worth_interrupting` at or above this may be spoken.
    pub nudge_at: f64,
    /// Notifications from these app names are never triaged.
    pub ignore_apps: Vec<String>,
    /// Seconds between calendar polls; 0 turns calendar triage off.
    pub calendar_poll_secs: u64,
}

impl Default for TriageConfig {
    fn default() -> Self {
        TriageConfig {
            per_hour: 60,
            nudge_at: 0.9,
            ignore_apps: Vec::new(),
            calendar_poll_secs: 60,
        }
    }
}

/// Something that happened on the phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Incoming {
    /// "notification", "sms", "message", "call" or "calendar".
    pub source: String,
    pub app: String,
    pub title: String,
    pub body: String,
}

/// Why an event was not triaged (logged at debug level, and for tests).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Skipped {
    NoConsent,
    Offline,
    Ignored,
    Repeat,
    OverQuota,
    Failed(String),
}

const BUCKETS: [&str; 4] = ["act_now", "today", "later", "ignore"];
const REPEAT_WINDOW: Duration = Duration::from_secs(600);
const HOUR: Duration = Duration::from_secs(3600);
/// Title and body are cut to this many characters before Jev sees them.
const MAX_TEXT: usize = 500;

/// The section 5.3 question set.
pub fn questions() -> std::collections::BTreeMap<String, Question> {
    let mut q = std::collections::BTreeMap::new();
    q.insert(
        "worth_interrupting".into(),
        Question::Noul {
            criteria: "Pilot should bring this to the user's attention now, interrupting what they are doing.".into(),
            yes: String::new(),
            no: String::new(),
        },
    );
    q.insert(
        "bucket".into(),
        Question::Choice {
            options: BUCKETS.iter().map(|b| (*b).to_owned()).collect(),
            criteria: "When the user needs to deal with this: act_now (within minutes), today, later, or ignore (no action needed).".into(),
            descriptions: Vec::new(),
        },
    );
    q.insert(
        "urgency".into(),
        Question::Score {
            legend: vec!["routine".into(), "time-sensitive".into(), "urgent".into()],
            criteria: "How urgent this is for the user.".into(),
        },
    );
    q
}

fn cut(s: &str) -> String {
    s.chars().take(MAX_TEXT).collect()
}

pub struct Triage {
    pipeline: Arc<Pipeline>,
    store: Arc<Store>,
    settings: Arc<Mutex<Settings>>,
    offline: Offline,
    adapters: Arc<Adapters>,
    cfg: TriageConfig,
    now: fn() -> LocalNow,
    recent: Mutex<HashMap<(String, String, String), Instant>>,
    sent: Mutex<VecDeque<Instant>>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

impl Triage {
    pub fn new(
        pipeline: Arc<Pipeline>,
        store: Arc<Store>,
        settings: Arc<Mutex<Settings>>,
        offline: Offline,
        adapters: Arc<Adapters>,
        cfg: TriageConfig,
        now: fn() -> LocalNow,
    ) -> Triage {
        Triage {
            pipeline,
            store,
            settings,
            offline,
            adapters,
            cfg,
            now,
            recent: Mutex::new(HashMap::new()),
            sent: Mutex::new(VecDeque::new()),
        }
    }

    pub fn config(&self) -> &TriageConfig {
        &self.cfg
    }

    /// Whether triage may run now: consent given, privacy switch off.
    pub fn active(&self) -> bool {
        lock(&self.settings).consent.triage && !self.offline.is_offline()
    }

    fn admit(&self, ev: &Incoming) -> Result<(), Skipped> {
        if !lock(&self.settings).consent.triage {
            return Err(Skipped::NoConsent);
        }
        if self.offline.is_offline() {
            return Err(Skipped::Offline);
        }
        let own = ["Pilot", "shoal-pilot", "pilotd"];
        if (ev.title.trim().is_empty() && ev.body.trim().is_empty())
            || own.contains(&ev.app.as_str())
            || self.cfg.ignore_apps.iter().any(|a| a == &ev.app)
        {
            return Err(Skipped::Ignored);
        }
        let key = (ev.app.clone(), ev.title.clone(), ev.body.clone());
        {
            let mut recent = lock(&self.recent);
            recent.retain(|_, t| t.elapsed() < REPEAT_WINDOW);
            if recent.contains_key(&key) {
                return Err(Skipped::Repeat);
            }
            recent.insert(key, Instant::now());
        }
        let mut sent = lock(&self.sent);
        while sent.front().is_some_and(|t| t.elapsed() >= HOUR) {
            sent.pop_front();
        }
        if sent.len() >= self.cfg.per_hour as usize {
            return Err(Skipped::OverQuota);
        }
        sent.push_back(Instant::now());
        Ok(())
    }

    /// Triages one event: Jev, the local list, and a spoken nudge when it
    /// qualifies.
    pub async fn handle(&self, ev: &Incoming) -> Result<TriageItem, Skipped> {
        self.admit(ev).inspect_err(|why| {
            log::debug!("triage skipped ({why:?}) for {} from {}", ev.source, ev.app);
        })?;
        let redactor = self.pipeline.redactor();
        let mut map = redactor.redact("").map;
        let me = self.pipeline.own_name();
        let title = crate::redact::for_jev(&redactor.redact_with(&cut(&ev.title), &mut map), &me);
        let body = crate::redact::for_jev(&redactor.redact_with(&cut(&ev.body), &mut map), &me);
        let now = (self.now)();
        let req = DecideRequest {
            state: json!({
                "event": {"source": ev.source, "app": ev.app, "title": title, "body": body},
                "context": {"time": now.hhmm(), "weekday": now.weekday},
            }),
            questions: questions(),
        };
        let answers = self
            .pipeline
            .jev()
            .decide(&req, "triage")
            .await
            .map_err(|e| {
                log::warn!("triage: {e}");
                Skipped::Failed(e.to_string())
            })?;
        let interrupt = match answers.get("worth_interrupting") {
            Some(Answer::Noul { p }) => *p,
            _ => return Err(Skipped::Failed("no worth_interrupting".into())),
        };
        let bucket = answers
            .get("bucket")
            .and_then(Answer::top)
            .ok_or_else(|| Skipped::Failed("no bucket".into()))?
            .to_owned();
        let urgency = match answers.get("urgency") {
            Some(Answer::Score { value, .. }) => *value,
            _ => return Err(Skipped::Failed("no urgency".into())),
        };
        let mut item = TriageItem {
            id: 0,
            ts_ms: store::now_ms(),
            source: ev.source.clone(),
            app: ev.app.clone(),
            title: ev.title.clone(),
            body: ev.body.clone(),
            bucket,
            urgency,
            interrupt,
        };
        match self.store.add_triage(&item) {
            Ok(id) => item.id = id,
            Err(e) => log::warn!("triage list: {e}"),
        }
        let nudges = lock(&self.settings).consent.spoken_nudges;
        if interrupt >= self.cfg.nudge_at && nudges && !self.offline.is_offline() {
            self.adapters.speech.say(&nudge_text(&item));
        }
        Ok(item)
    }
}

/// What a spoken nudge says: where it came from and its title, never the
/// body.
pub fn nudge_text(item: &TriageItem) -> String {
    let what = match item.source.as_str() {
        "sms" | "message" => "Message",
        "call" => "Missed call",
        "calendar" => "Calendar",
        _ => item.app.as_str(),
    };
    let title: String = item.title.chars().take(80).collect();
    if title.is_empty() {
        what.to_owned()
    } else {
        format!("{what}: {title}")
    }
}

/// The source of a notification, from its Sailfish category hint.
pub fn source_of(category: &str) -> Option<&'static str> {
    const SKIP: [&str; 6] = [
        "x-nemo.transfer",
        "x-nemo.battery",
        "x-nemo.usb",
        "x-nemo.connectivity",
        "x-nemo.general.warning",
        "device",
    ];
    if SKIP.iter().any(|p| category.starts_with(p)) {
        return None;
    }
    Some(
        if category.starts_with("x-nemo.messaging.sms")
            || category.starts_with("x-nemo.messaging.mms")
        {
            "sms"
        } else if category.starts_with("x-nemo.messaging") || category.starts_with("im.") {
            "message"
        } else if category.starts_with("x-nemo.call.missed") {
            "call"
        } else {
            "notification"
        },
    )
}

/// Reads a `Notify` call's arguments. `None` for calls not worth
/// triaging (transient, system categories, progress updates).
pub fn from_notify(msg: &zbus::Message) -> Option<Incoming> {
    use zbus::zvariant::OwnedValue;
    type Notify = (
        String,
        u32,
        String,
        String,
        String,
        Vec<String>,
        HashMap<String, OwnedValue>,
        i32,
    );
    let (app, _replaces, _icon, summary, body, _actions, hints, _timeout): Notify =
        msg.body().deserialize().ok()?;
    let hint = |k: &str| {
        hints
            .get(k)
            .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
            .unwrap_or_default()
    };
    let transient = hints
        .get("transient")
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(false);
    if transient {
        return None;
    }
    let source = source_of(&hint("category"))?;
    // Sailfish apps often leave summary and body empty and fill the
    // preview hints instead.
    let pick = |a: String, b: String| if a.trim().is_empty() { b } else { a };
    Some(Incoming {
        source: source.to_owned(),
        app,
        title: pick(summary, hint("x-nemo-preview-summary")),
        body: pick(body, hint("x-nemo-preview-body")),
    })
}

/// Turns `conn` (a fresh session-bus connection, used for nothing else)
/// into a monitor of `Notify` calls and sends each one worth triaging.
/// Returns when the bus goes away or the receiver is dropped.
pub async fn watch_notifications(
    conn: zbus::Connection,
    tx: tokio::sync::mpsc::Sender<Incoming>,
) -> zbus::Result<()> {
    use futures_util::StreamExt as _;
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::MethodCall)
        .interface("org.freedesktop.Notifications")?
        .member("Notify")?
        .build();
    zbus::fdo::MonitoringProxy::new(&conn)
        .await?
        .become_monitor(&[rule], 0)
        .await?;
    let mut stream = zbus::MessageStream::from(conn);
    while let Some(msg) = stream.next().await {
        let Ok(msg) = msg else { continue };
        let h = msg.header();
        if h.member().map(zbus::names::MemberName::as_str) != Some("Notify") {
            continue;
        }
        if let Some(ev) = from_notify(&msg) {
            if tx.send(ev).await.is_err() {
                break;
            }
        }
    }
    Ok(())
}

/// Calendar changes between polls (section 5.3, "calendar change").
#[derive(Default)]
pub struct CalendarWatch {
    /// The events of the previous read and the window `[from, to)` read.
    last: Option<(Vec<CalendarEvent>, (i64, i64))>,
}

/// How far ahead the calendar is watched.
pub const CALENDAR_AHEAD: i64 = 7 * 86_400;

impl CalendarWatch {
    /// Compares `now`, read for `window`, with the previous read. The first
    /// read only sets the baseline: what was already there is not news.
    /// The window moves with time, so an event that has ended since is not
    /// "removed", and one that only came into the week ahead is not "added".
    pub fn changes(
        &mut self,
        now: &[CalendarEvent],
        window: (i64, i64),
        when: impl Fn(i64) -> String,
    ) -> Vec<Incoming> {
        let Some((prev, (_, prev_to))) = self.last.replace((now.to_vec(), window)) else {
            return Vec::new();
        };
        let (from, _) = window;
        // Only what both reads could see is compared.
        let prev: Vec<&CalendarEvent> = prev.iter().filter(|p| p.end > from).collect();
        let now: Vec<&CalendarEvent> = now.iter().filter(|e| e.start < prev_to).collect();
        let ev = |title: &str, body: String| Incoming {
            source: "calendar".into(),
            app: "Calendar".into(),
            title: title.to_owned(),
            body,
        };
        let mut out = Vec::new();
        for e in &now {
            if prev
                .iter()
                .any(|p| p.title == e.title && p.start == e.start)
            {
                continue;
            }
            if prev.iter().any(|p| p.title == e.title) {
                out.push(ev(&e.title, format!("moved to {}", when(e.start))));
            } else {
                out.push(ev(&e.title, format!("added for {}", when(e.start))));
            }
        }
        for p in &prev {
            if !now.iter().any(|e| e.title == p.title) {
                out.push(ev(&p.title, format!("removed; was {}", when(p.start))));
            }
        }
        out
    }
}

/// "Fri 14:30" in local time.
pub fn short_when(epoch: i64) -> String {
    let t = crate::localtime::at(epoch);
    let day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        .get(t.weekday as usize)
        .copied()
        .unwrap_or("");
    format!("{day} {}", t.hhmm())
}

/// What one calendar poll did, for logging and tests.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalendarPoll {
    /// Triage is off (no consent, or the privacy switch): mkcal not touched.
    Inactive,
    /// The calendar's change stamp is the one already read: nothing read.
    Unchanged,
    /// The calendar was read.
    Read,
    /// It could not be read.
    Failed,
}

/// The calendar half of triage: one poll's state.
#[derive(Default)]
pub struct CalendarPoller {
    watch: CalendarWatch,
    /// The stamp of the last successful read.
    stamp: Option<u64>,
}

impl CalendarPoller {
    /// One poll. Nothing at all is read while triage is off, and the baseline
    /// is dropped, so turning triage on starts from a fresh one and does not
    /// report what changed while it was off. While on, the database is read
    /// only when its change stamp moved (`Calendar::stamp`).
    pub async fn poll(
        &mut self,
        adapters: &Adapters,
        triage: &Triage,
        tx: &tokio::sync::mpsc::Sender<Incoming>,
    ) -> Result<CalendarPoll, ()> {
        if !triage.active() {
            self.watch = CalendarWatch::default();
            self.stamp = None;
            return Ok(CalendarPoll::Inactive);
        }
        let stamp = adapters.calendar.stamp();
        if stamp.is_some() && stamp == self.stamp {
            return Ok(CalendarPoll::Unchanged);
        }
        let now = (triage.now)().epoch;
        let window = (now, now + CALENDAR_AHEAD);
        let events = match adapters.calendar.events(window.0, window.1, 200) {
            Ok(e) => e,
            Err(e) => {
                log::debug!("calendar triage: {e}");
                return Ok(CalendarPoll::Failed);
            }
        };
        self.stamp = stamp;
        for c in self.watch.changes(&events, window, short_when) {
            tx.send(c).await.map_err(|_| ())?;
        }
        Ok(CalendarPoll::Read)
    }
}

/// Polls the calendar every `[triage] calendar_poll_secs` while triage is on
/// and sends the changes. With triage off mkcal's database is never opened;
/// with it on, it is opened only after the database file changed.
pub async fn watch_calendar(
    adapters: Arc<Adapters>,
    triage: Arc<Triage>,
    tx: tokio::sync::mpsc::Sender<Incoming>,
) {
    let secs = triage.config().calendar_poll_secs;
    if secs == 0 {
        return;
    }
    let mut poller = CalendarPoller::default();
    let mut tick = tokio::time::interval(Duration::from_secs(secs));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tick.tick().await;
        if poller.poll(&adapters, &triage, &tx).await.is_err() {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn categories() {
        assert_eq!(source_of("x-nemo.messaging.sms"), Some("sms"));
        assert_eq!(source_of("x-nemo.messaging.im"), Some("message"));
        assert_eq!(source_of("x-nemo.call.missed"), Some("call"));
        assert_eq!(source_of(""), Some("notification"));
        assert_eq!(source_of("x-nemo.battery.lowbattery"), None);
        assert_eq!(source_of("x-nemo.transfer"), None);
    }

    #[test]
    fn calendar_changes_after_the_baseline() {
        let e = |t: &str, s: i64| CalendarEvent {
            title: t.into(),
            start: s,
            end: s + 60,
            all_day: false,
            location: None,
        };
        let mut w = CalendarWatch::default();
        let when = |s: i64| format!("@{s}");
        let week = (0, 1000);
        assert!(w
            .changes(&[e("Dentist", 100), e("Standup", 200)], week, when)
            .is_empty());
        let c = w.changes(&[e("Dentist", 150), e("Lunch", 300)], week, when);
        let got: Vec<(String, String)> = c.into_iter().map(|i| (i.title, i.body)).collect();
        assert_eq!(
            got,
            [
                ("Dentist".to_owned(), "moved to @150".to_owned()),
                ("Lunch".to_owned(), "added for @300".to_owned()),
                ("Standup".to_owned(), "removed; was @200".to_owned()),
            ]
        );
        assert!(w
            .changes(&[e("Dentist", 150), e("Lunch", 300)], week, when)
            .is_empty());
    }

    #[test]
    fn the_moving_window_is_not_a_change() {
        let e = |t: &str, s: i64| CalendarEvent {
            title: t.into(),
            start: s,
            end: s + 60,
            all_day: false,
            location: None,
        };
        let when = |s: i64| format!("@{s}");
        let mut w = CalendarWatch::default();
        assert!(w
            .changes(&[e("Standup", 100), e("Lunch", 500)], (0, 1000), when)
            .is_empty());
        // An hour later: Standup has ended and Review came into the week
        // ahead. Neither is news.
        assert!(w
            .changes(&[e("Lunch", 500), e("Review", 1500)], (200, 1600), when)
            .is_empty());
        // A real addition inside both windows still is.
        let c = w.changes(
            &[e("Lunch", 500), e("Call", 700), e("Review", 1500)],
            (210, 1610),
            when,
        );
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].body, "added for @700");
    }

    #[test]
    fn nudges_never_include_the_body() {
        let item = TriageItem {
            id: 1,
            ts_ms: 0,
            source: "sms".into(),
            app: "Messages".into(),
            title: "Anna Virtanen".into(),
            body: "the door code is 4411".into(),
            bucket: "act_now".into(),
            urgency: 2.0,
            interrupt: 0.95,
        };
        assert_eq!(nudge_text(&item), "Message: Anna Virtanen");
    }
}
