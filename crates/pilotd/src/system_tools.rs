// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The system tool registry of spec section 6.2: capabilities that are not
//! Keel apps, backed by the Sailfish adapters. The deterministic handlers
//! call the same tools, so a timer set by Jev routing and one set by Qwen
//! go through one validated code path.

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::{json, Value};

use crate::adapters::clock::next_local;
use crate::adapters::{range_window, Adapters, Toggle};
use crate::intents::{DayRange, MediaAction};
use crate::localtime::LocalNow;
use crate::schema::Validator;
use crate::tools::{Confirm, Registry, ToolError, ToolExecutor, ToolOutput, ToolSpec};

pub struct SystemTools {
    pub adapters: Arc<Adapters>,
    pub now: fn() -> LocalNow,
    pub local_at: fn(i64) -> LocalNow,
}

fn schema(v: &Value) -> Validator {
    Validator::new(v.clone()).expect("system tool schemas are static and valid")
}

#[allow(clippy::too_many_arguments, reason = "a table of tool declarations")]
fn spec(
    name: &str,
    title: &str,
    description: &str,
    input: &Value,
    confirm: Confirm,
    read_only: bool,
    open_world: bool,
    domain: &str,
) -> ToolSpec {
    ToolSpec {
        name: name.into(),
        title: title.into(),
        description: description.into(),
        input: schema(input),
        output: None,
        confirm,
        read_only,
        destructive: false,
        open_world,
        domain: domain.into(),
    }
}

/// Section 6.2's table. The bool is whether this build can execute it;
/// unavailable tools are not offered to the model.
#[allow(clippy::too_many_lines, reason = "one declaration per tool")]
pub fn specs() -> Vec<(ToolSpec, bool)> {
    let hhmm = json!({"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"});
    vec![
        (
            spec(
                "calendar.query",
                "Check calendar",
                "List calendar events for today, tomorrow, a named day of the week (the next one), the next seven days, or the next event.",
                &json!({"type": "object", "properties": {
                    "range": {"enum": ["today", "tomorrow", "week", "next",
                        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]}},
                    "required": ["range"], "additionalProperties": false}),
                Confirm::Never,
                true,
                false,
                "calendar",
            ),
            true,
        ),
        (
            spec(
                "calendar.add",
                "Add to calendar",
                "Add an event to the calendar.",
                &json!({"type": "object", "properties": {
                    "title": {"type": "string", "minLength": 1, "maxLength": 200},
                    "start": {"type": "string", "format": "date-time"},
                    "end": {"type": "string", "format": "date-time"},
                    "location": {"type": "string", "maxLength": 200}},
                    "required": ["title", "start"], "additionalProperties": false}),
                Confirm::Always,
                false,
                false,
                "calendar",
            ),
            false,
        ),
        (
            spec(
                "contacts.lookup",
                "Find contact",
                "Find contacts by name. Returns names, phone numbers and email addresses.",
                &json!({"type": "object", "properties": {
                    "query": {"type": "string", "minLength": 1, "maxLength": 100}},
                    "required": ["query"], "additionalProperties": false}),
                Confirm::Never,
                true,
                false,
                "messaging",
            ),
            true,
        ),
        (
            spec(
                "messages.send",
                "Send message",
                "Send an SMS to a phone number or contact.",
                &json!({"type": "object", "properties": {
                    "to": {"type": "string", "minLength": 1, "maxLength": 100},
                    "text": {"type": "string", "minLength": 1, "maxLength": 1600}},
                    "required": ["to", "text"], "additionalProperties": false}),
                Confirm::Always,
                false,
                true,
                "messaging",
            ),
            false,
        ),
        (
            spec(
                "call.dial",
                "Call",
                "Start a phone call to a number.",
                &json!({"type": "object", "properties": {
                    "number": {"type": "string", "minLength": 1, "maxLength": 40}},
                    "required": ["number"], "additionalProperties": false}),
                Confirm::Always,
                false,
                true,
                "messaging",
            ),
            true,
        ),
        (
            spec(
                "reminder.create",
                "Create reminder",
                "Create a one-off reminder, either in_seconds from now or at a local time (HH:MM) with an optional day_offset (1 = tomorrow).",
                &json!({"type": "object", "properties": {
                    "text": {"type": "string", "minLength": 1, "maxLength": 200, "description": "What to remind about, as the person would say it after \"remind me to\": \"stretch\", \"call the dentist\". Not the time."},
                    "in_seconds": {"type": "integer", "minimum": 1, "maximum": 31_536_000},
                    "time": hhmm,
                    "day_offset": {"type": "integer", "minimum": 0, "maximum": 365}},
                    "required": ["text"], "additionalProperties": false,
                    "oneOf": [{"required": ["in_seconds"]}, {"required": ["time"]}]}),
                Confirm::Never,
                false,
                false,
                "system",
            ),
            true,
        ),
        (
            spec(
                "alarm.set",
                "Set alarm",
                "Set a one-off alarm at the next occurrence of a local time (HH:MM, 24-hour).",
                &json!({"type": "object", "properties": {
                    "time": hhmm,
                    "label": {"type": "string", "maxLength": 60}},
                    "required": ["time"], "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "system",
            ),
            true,
        ),
        (
            spec(
                "clock.cancel",
                "Cancel timer or alarm",
                "Cancel a timer, alarm or reminder by its cookie (as timer.set, alarm.set or reminder.create returned it).",
                &json!({"type": "object", "properties": {
                    "cookie": {"type": "integer", "minimum": 1, "maximum": 4_294_967_295_u64}},
                    "required": ["cookie"], "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "system",
            ),
            true,
        ),
        (
            spec(
                "timer.set",
                "Set timer",
                "Start a countdown timer.",
                &json!({"type": "object", "properties": {
                    "seconds": {"type": "integer", "minimum": 1, "maximum": 604_800},
                    "label": {"type": "string", "maxLength": 60}},
                    "required": ["seconds"], "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "system",
            ),
            true,
        ),
        (
            spec(
                "media.control",
                "Media",
                "Control the current media player.",
                &json!({"type": "object", "properties": {
                    "action": {"enum": ["play", "pause", "toggle", "stop", "next", "previous"]}},
                    "required": ["action"], "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "media",
            ),
            true,
        ),
        (
            spec(
                "device.toggle",
                "Device setting",
                "Turn Wi-Fi, Bluetooth, mobile data or flight mode on or off.",
                &json!({"type": "object", "properties": {
                    "target": {"enum": ["wifi", "bluetooth", "mobile_data", "flight_mode"]},
                    "on": {"type": "boolean"}},
                    "required": ["target", "on"], "additionalProperties": false}),
                Confirm::When(|a| a.get("target").and_then(Value::as_str) == Some("flight_mode")),
                false,
                false,
                "system",
            ),
            true,
        ),
        (
            spec(
                "notifications.read",
                "Read notifications",
                "List recent notifications.",
                &json!({"type": "object", "properties": {
                    "limit": {"type": "integer", "minimum": 1, "maximum": 20}},
                    "additionalProperties": false}),
                Confirm::Never,
                true,
                false,
                "system",
            ),
            false,
        ),
        (
            spec(
                "camera.capture",
                "Camera",
                "Ask the user to take a photo for you to look at. Only when they asked about something in front of them.",
                &json!({"type": "object", "properties": {}, "additionalProperties": false}),
                Confirm::Never,
                true,
                false,
                "vision",
            ),
            // The pipeline answers it with a camera card; the person
            // takes the photo (user-initiated only).
            true,
        ),
        // Sailfish's own apps, through the entry points they publish
        // (adapters::stock): each opens the app with the work filled in and
        // the person finishes it there, so none needs a card.
        (
            spec(
                "email.draft",
                "Draft an e-mail",
                "Open a new e-mail in the phone's Email app, filled in, for the person to check and send themselves. Nothing is sent. Look up an address with contacts.lookup first when given a name.",
                &json!({"type": "object", "properties": {
                    "to": {"type": "string", "maxLength": 500, "description": "Comma-separated e-mail addresses"},
                    "subject": {"type": "string", "maxLength": 300},
                    "body": {"type": "string", "maxLength": 8000}},
                    "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "messaging",
            ),
            true,
        ),
        (
            spec(
                "messages.draft",
                "Draft a text message",
                "Open a text message (SMS) to a phone number in the phone's Messages app with the text written in, for the person to send themselves. Nothing is sent. Look the number up with contacts.lookup first when given a name.",
                &json!({"type": "object", "properties": {
                    "to": {"type": "string", "minLength": 3, "maxLength": 40, "description": "Phone number"},
                    "text": {"type": "string", "minLength": 1, "maxLength": 1000}},
                    "required": ["to", "text"], "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "messaging",
            ),
            true,
        ),
        (
            spec(
                "device.status",
                "Check a setting",
                "Whether Wi-Fi, Bluetooth, mobile data or flight mode is on right now.",
                &json!({"type": "object", "properties": {
                    "target": {"enum": ["wifi", "bluetooth", "mobile_data", "flight_mode"]}},
                    "required": ["target"], "additionalProperties": false}),
                Confirm::Never,
                true,
                false,
                "system",
            ),
            true,
        ),
        (
            spec(
                "notes.create",
                "Make a note",
                "Add a note to the phone's Notes app with this text, and open it there.",
                &json!({"type": "object", "properties": {
                    "text": {"type": "string", "minLength": 1, "maxLength": 8000}},
                    "required": ["text"], "additionalProperties": false}),
                Confirm::Never,
                false,
                false,
                "notes",
            ),
            true,
        ),
        (
            spec(
                "settings.open",
                "Open a settings page",
                "Open a page of the phone's Settings app for the person to change something themselves.",
                &json!({"type": "object", "properties": {
                    "page": {"enum": ["about", "battery", "bluetooth", "date_time", "developer_mode", "device_lock", "display", "flight_mode", "gestures", "location", "language", "lock_screen", "mobile_network", "nfc", "privacy_switch", "sounds", "storage", "tethering", "text_input", "updates", "usb", "vpn", "wifi"]}},
                    "required": ["page"], "additionalProperties": false}),
                Confirm::Never,
                true,
                false,
                "system",
            ),
            true,
        ),
    ]
}

/// Registers every system tool against `exec`.
pub fn register(registry: &mut Registry, exec: &Arc<SystemTools>) {
    for (spec, available) in specs() {
        registry.add(spec, available, exec.clone());
    }
}

/// A string argument, trimmed: the model wrote a placeholder with a space
/// before it, and the space went into the e-mail's To field.
fn arg<'a>(args: &'a Value, k: &str) -> Option<&'a str> {
    args.get(k)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

fn hhmm(s: &str) -> Option<(u32, u32)> {
    let (h, m) = s.split_once(':')?;
    Some((h.parse().ok()?, m.parse().ok()?))
}

/// "5 minutes", "1 hour 30 minutes", "45 seconds".
pub fn describe_duration(secs: u32) -> String {
    let (h, m, s) = (secs / 3600, (secs % 3600) / 60, secs % 60);
    let unit = |n: u32, one: &str, many: &str| format!("{n} {}", if n == 1 { one } else { many });
    let mut parts = Vec::new();
    if h > 0 {
        parts.push(unit(h, "hour", "hours"));
    }
    if m > 0 {
        parts.push(unit(m, "minute", "minutes"));
    }
    if s > 0 || parts.is_empty() {
        parts.push(unit(s, "second", "seconds"));
    }
    parts.join(" ")
}

impl SystemTools {
    fn hm(&self, epoch: i64) -> String {
        (self.local_at)(epoch).hhmm()
    }

    fn calendar(&self, args: &Value) -> Result<ToolOutput, ToolError> {
        let range = match arg(args, "range") {
            Some("tomorrow") => DayRange::Tomorrow,
            Some("week") => DayRange::Week,
            Some("next") => DayRange::Next,
            Some(day) => crate::intents::WEEKDAYS
                .iter()
                .position(|d| *d == day)
                .and_then(|i| u32::try_from(i).ok())
                .map_or(DayRange::Today, DayRange::Weekday),
            None => DayRange::Today,
        };
        let now = (self.now)();
        let (from, to) = range_window(range, &now);
        let limit = if range == DayRange::Next { 1 } else { 20 };
        let events = self.adapters.calendar.events(from, to, limit)?;
        let day_name;
        let when = match range {
            DayRange::Today => "today",
            DayRange::Tomorrow => "tomorrow",
            DayRange::Week => "in the next seven days",
            DayRange::Next => "coming up",
            DayRange::Weekday(d) if d == now.weekday => "today",
            DayRange::Weekday(d) => {
                let name = crate::intents::WEEKDAYS[d as usize % 7];
                day_name = format!("on {}{}", name[..1].to_uppercase(), &name[1..]);
                day_name.as_str()
            }
        };
        let summary = if events.is_empty() {
            format!("Nothing on your calendar {when}.")
        } else {
            let items: Vec<String> = events
                .iter()
                .map(|e| {
                    if e.all_day {
                        format!("{} (all day)", e.title)
                    } else {
                        format!("{} {}", self.hm(e.start), e.title)
                    }
                })
                .collect();
            let n = events.len();
            if range == DayRange::Next {
                format!("Next: {}.", items.join(""))
            } else {
                format!(
                    "{n} event{} {when}: {}.",
                    if n == 1 { "" } else { "s" },
                    items.join("; ")
                )
            }
        };
        Ok(ToolOutput {
            private: false,
            untrusted: false,
            summary,
            data: json!({ "events": events }),
        })
    }
}

#[async_trait]
impl ToolExecutor for SystemTools {
    #[allow(clippy::too_many_lines, reason = "one arm per system tool")]
    async fn call(&self, tool: &str, args: &Value) -> Result<ToolOutput, ToolError> {
        let a = &self.adapters;
        match tool {
            "clock.cancel" => {
                let cookie = args
                    .get("cookie")
                    .and_then(Value::as_u64)
                    .and_then(|c| u32::try_from(c).ok())
                    .ok_or_else(|| ToolError::Failed("cookie".into()))?;
                let cancelled = a.clock.cancel(cookie).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: if cancelled {
                        "Cancelled.".into()
                    } else {
                        "It had already gone off or been cancelled.".into()
                    },
                    data: json!({"cookie": cookie, "cancelled": cancelled}),
                })
            }
            "timer.set" => {
                let secs = args
                    .get("seconds")
                    .and_then(Value::as_u64)
                    .and_then(|s| u32::try_from(s).ok())
                    .ok_or_else(|| ToolError::Failed("seconds".into()))?;
                let label = arg(args, "label");
                let cookie = a.clock.set_timer(secs, label).await?;
                let d = describe_duration(secs);
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: match label {
                        Some(l) => format!("Timer set for {d} ({l})."),
                        None => format!("Timer set for {d}."),
                    },
                    data: json!({"cookie": cookie, "seconds": secs}),
                })
            }
            "alarm.set" => {
                let (h, m) = arg(args, "time")
                    .and_then(hhmm)
                    .ok_or_else(|| ToolError::Failed("time".into()))?;
                let cookie = a.clock.set_alarm(h, m, arg(args, "label")).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("Alarm set for {h:02}:{m:02}."),
                    data: json!({"cookie": cookie, "time": format!("{h:02}:{m:02}"),
                                 "at": next_local(&(self.now)(), h, m, 0)}),
                })
            }
            "reminder.create" => {
                let text = arg(args, "text").ok_or_else(|| ToolError::Failed("text".into()))?;
                let now = (self.now)();
                let (at, when) = if let Some(s) = args.get("in_seconds").and_then(Value::as_i64) {
                    let secs = u32::try_from(s).unwrap_or(u32::MAX);
                    (now.epoch + s, format!("in {}", describe_duration(secs)))
                } else {
                    let (h, m) = arg(args, "time")
                        .and_then(hhmm)
                        .ok_or_else(|| ToolError::Failed("time".into()))?;
                    let day = args
                        .get("day_offset")
                        .and_then(Value::as_u64)
                        .and_then(|d| u32::try_from(d).ok())
                        .unwrap_or(0);
                    let at = next_local(&now, h, m, day);
                    let day_word = if at >= now.local_time(2, 0, 0) {
                        " later"
                    } else if at >= now.local_time(1, 0, 0) {
                        " tomorrow"
                    } else {
                        ""
                    };
                    (at, format!("at {h:02}:{m:02}{day_word}"))
                };
                let cookie = a.clock.create_reminder(text, at).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("I'll remind you to {text} {when}."),
                    data: json!({"cookie": cookie, "at": at}),
                })
            }
            "media.control" => {
                let action = arg(args, "action")
                    .and_then(MediaAction::parse)
                    .ok_or_else(|| ToolError::Failed("action".into()))?;
                let player = a.media.control(action).await?;
                let summary = match action {
                    MediaAction::Play => "Playing.",
                    MediaAction::Pause => "Paused.",
                    MediaAction::Toggle => "Done.",
                    MediaAction::Stop => "Stopped.",
                    MediaAction::Next => "Next track.",
                    MediaAction::Previous => "Previous track.",
                };
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: summary.into(),
                    data: json!({"player": player, "action": action}),
                })
            }
            "calendar.query" => self.calendar(args),
            "contacts.lookup" => {
                let q = arg(args, "query").ok_or_else(|| ToolError::Failed("query".into()))?;
                let hits = a.contacts.lookup(q, 5)?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("Found {} contact(s).", hits.len()),
                    data: json!({"contacts": hits}),
                })
            }
            "call.dial" => {
                let n = arg(args, "number").ok_or_else(|| ToolError::Failed("number".into()))?;
                a.telephony.dial(n).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("Calling {n}."),
                    data: json!({}),
                })
            }
            "messages.send" => {
                let to = arg(args, "to").ok_or_else(|| ToolError::Failed("to".into()))?;
                let text = arg(args, "text").ok_or_else(|| ToolError::Failed("text".into()))?;
                a.telephony.send_sms(to, text).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("Message sent to {to}."),
                    data: json!({}),
                })
            }
            "messages.draft" => {
                let to = arg(args, "to").ok_or_else(|| ToolError::Failed("to".into()))?;
                let number = crate::adapters::telephony::dialable(to).ok_or_else(|| {
                    ToolError::Invalid("not a phone number; look it up with contacts.lookup".into())
                })?;
                let text = arg(args, "text").ok_or_else(|| ToolError::Failed("text".into()))?;
                a.stock.compose_sms(&number, text).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: "The message is open in Messages for the person to send.".into(),
                    data: json!({}),
                })
            }
            "device.status" => {
                let target = arg(args, "target")
                    .and_then(Toggle::parse)
                    .ok_or_else(|| ToolError::Failed("target".into()))?;
                let on = a.toggles.get(target).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!(
                        "{} is {}.",
                        arg(args, "target").unwrap_or("").replace('_', " "),
                        if on { "on" } else { "off" }
                    ),
                    data: json!({"on": on}),
                })
            }
            "email.draft" => {
                let to = arg(args, "to").unwrap_or("");
                let subject = arg(args, "subject").unwrap_or("");
                let body = arg(args, "body").unwrap_or("");
                let ready = a.stock.compose_email(to, subject, body).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: if ready && to.trim().is_empty() {
                        "The e-mail is open in Email with no recipient: the person adds who it \
                         goes to, checks it and sends it. Say so; do not say who it is addressed to."
                            .into()
                    } else if ready {
                        "The e-mail is open in Email for the person to check and send.".into()
                    } else {
                        "No draft was made: there is no e-mail account on the phone. Email is open so the person can add one (Settings > Accounts).".into()
                    },
                    data: json!({"drafted": ready}),
                })
            }
            "notes.create" => {
                let text = arg(args, "text").ok_or_else(|| ToolError::Failed("text".into()))?;
                a.stock.new_note(text).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: "The note is in Notes.".into(),
                    data: json!({}),
                })
            }
            "settings.open" => {
                let page = arg(args, "page").ok_or_else(|| ToolError::Failed("page".into()))?;
                let path = crate::adapters::stock::settings_path(page)
                    .ok_or_else(|| ToolError::Failed("page".into()))?;
                a.stock.open_settings(path).await?;
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("Settings is open at {}.", page.replace('_', " ")),
                    data: json!({}),
                })
            }
            "device.toggle" => {
                let target = arg(args, "target")
                    .and_then(Toggle::parse)
                    .ok_or_else(|| ToolError::Failed("target".into()))?;
                let on = args.get("on").and_then(Value::as_bool).unwrap_or(false);
                a.toggles.set(target, on).await?;
                let name = match target {
                    Toggle::Wifi => "Wi-Fi",
                    Toggle::Bluetooth => "Bluetooth",
                    Toggle::MobileData => "Mobile data",
                    Toggle::FlightMode => "Flight mode",
                };
                Ok(ToolOutput {
                    private: false,
                    untrusted: false,
                    summary: format!("{name} {}.", if on { "on" } else { "off" }),
                    data: json!({}),
                })
            }
            other => Err(ToolError::Unavailable(format!("{other} is not available"))),
        }
    }
}

/// A one-line description of a pending call for its confirmation card.
pub fn card_detail(tool: &str, args: &Value) -> String {
    let s = |k: &str| arg(args, k).unwrap_or("?").to_owned();
    match tool {
        "messages.send" => format!("To {}: \u{201c}{}\u{201d}", s("to"), s("text")),
        "call.dial" => format!("Call {}", s("number")),
        "calendar.add" => format!("{} at {}", s("title"), s("start")),
        "device.toggle" => format!(
            "Turn {} {}",
            s("target").replace('_', " "),
            if args.get("on").and_then(Value::as_bool) == Some(true) {
                "on"
            } else {
                "off"
            }
        ),
        "memory.remember" => format!("Remember \u{201c}{}\u{201d}", s("fact")),
        _ => serde_json::to_string(args).unwrap_or_default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_spec_schema_compiles_and_rejects_junk() {
        for (s, _) in specs() {
            assert!(
                !s.input.is_valid(&json!({"unexpected": true})),
                "{}",
                s.name
            );
        }
    }

    #[test]
    fn reminder_needs_exactly_one_time_form() {
        let r = specs()
            .into_iter()
            .find(|(s, _)| s.name == "reminder.create")
            .unwrap()
            .0;
        assert!(r.input.is_valid(&json!({"text": "x", "in_seconds": 60})));
        assert!(r
            .input
            .is_valid(&json!({"text": "x", "time": "07:30", "day_offset": 1})));
        assert!(!r.input.is_valid(&json!({"text": "x"})));
        assert!(!r
            .input
            .is_valid(&json!({"text": "x", "in_seconds": 60, "time": "07:30"})));
        assert!(!r.input.is_valid(&json!({"text": "x", "time": "7:30"})));
    }

    #[test]
    fn confirmation_policy_matches_section_6_2() {
        let all = specs();
        let needs = |name: &str, args: Value| {
            all.iter()
                .find(|(s, _)| s.name == name)
                .unwrap()
                .0
                .needs_confirmation(&args)
        };
        assert!(needs("messages.send", json!({})));
        assert!(needs("call.dial", json!({})));
        assert!(needs("calendar.add", json!({})));
        assert!(needs(
            "device.toggle",
            json!({"target": "flight_mode", "on": true})
        ));
        assert!(!needs(
            "device.toggle",
            json!({"target": "wifi", "on": true})
        ));
        assert!(!needs("timer.set", json!({})));
        assert!(!needs("calendar.query", json!({})));
        assert!(!needs("contacts.lookup", json!({})));
    }

    #[test]
    fn durations_read_naturally() {
        assert_eq!(describe_duration(300), "5 minutes");
        assert_eq!(describe_duration(5400), "1 hour 30 minutes");
        assert_eq!(describe_duration(61), "1 minute 1 second");
    }
}
