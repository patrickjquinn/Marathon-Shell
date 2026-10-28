// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Timers, alarms and reminders through timed (`com.nokia.time` on the
//! **system** bus, method `add_event`), built the way the Clock app's
//! `Nemo.Alarms` plugin builds them (nemo-qml-plugin-alarms,
//! `AlarmObject::save`), so they appear in and can be edited from Clock.
//!
//! The wire format is timed's `Maemo::Timed::event_io_t`, marshalled as in
//! timed's `src/lib/event-io.cpp`:
//!
//! ```text
//! (i uuuuu s (a{ss}) u a((a{ss})u) a(u(a{ss})a(sb)) a(tuuuuu) i i a(sb))
//!  ticker, y m d h min, zone, attributes, flags, buttons, actions,
//!  recurrences, tsz_max, tsz_length, credential modifiers
//! ```

use std::collections::HashMap;

use async_trait::async_trait;
use serde::Serialize;
use zbus::zvariant::Type;

use super::{AdapterError, Clock, ClockItem};
use crate::localtime::LocalNow;

pub const TIMED_SERVICE: &str = "com.nokia.time";
pub const TIMED_PATH: &str = "/com/nokia/time";
pub const TIMED_INTERFACE: &str = "com.nokia.time";

/// timed `EventFlags` (src/server/flags.h).
pub mod flags {
    pub const ALARM: u32 = 1 << 0;
    pub const BOOT: u32 = 1 << 6;
    pub const REMINDER: u32 = 1 << 7;
    pub const KEEP_ALIVE: u32 = 1 << 11;
    pub const SINGLE_SHOT: u32 = 1 << 12;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Type, Default)]
pub struct Attributes {
    pub txt: HashMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Type)]
pub struct CredModifier {
    pub token: String,
    pub accrue: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Type)]
pub struct Button {
    pub attr: Attributes,
    pub snooze: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Type)]
pub struct Action {
    pub flags: u32,
    pub attr: Attributes,
    pub cred_modifiers: Vec<CredModifier>,
}

/// Bit masks, as `Maemo::Timed::Event::Recurrence`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Type)]
pub struct Recurrence {
    pub mins: u64,
    pub hour: u32,
    pub mday: u32,
    pub wday: u32,
    pub mons: u32,
    pub flags: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Type)]
pub struct EventIo {
    pub ticker: i32,
    pub t_year: u32,
    pub t_month: u32,
    pub t_day: u32,
    pub t_hour: u32,
    pub t_minute: u32,
    pub t_zone: String,
    pub attr: Attributes,
    pub flags: u32,
    pub buttons: Vec<Button>,
    pub actions: Vec<Action>,
    pub recrs: Vec<Recurrence>,
    pub tsz_max: i32,
    pub tsz_length: i32,
    pub cred_modifiers: Vec<CredModifier>,
}

impl EventIo {
    fn empty() -> EventIo {
        EventIo {
            ticker: 0,
            t_year: 0,
            t_month: 0,
            t_day: 0,
            t_hour: 0,
            t_minute: 0,
            t_zone: String::new(),
            attr: Attributes::default(),
            flags: 0,
            buttons: Vec::new(),
            actions: Vec::new(),
            recrs: Vec::new(),
            tsz_max: 0,
            tsz_length: 1,
            cred_modifiers: Vec::new(),
        }
    }

    fn set(&mut self, k: &str, v: impl Into<String>) {
        self.attr.txt.insert(k.to_owned(), v.into());
    }
}

fn ticker(epoch: i64) -> Result<i32, AdapterError> {
    // timed's ticker is a signed 32-bit time_t on the wire.
    i32::try_from(epoch).map_err(|_| AdapterError::Failed("time out of range".into()))
}

fn base(title: Option<&str>, created_ms: i64) -> EventIo {
    let mut ev = EventIo::empty();
    ev.flags = flags::KEEP_ALIVE | flags::REMINDER | flags::ALARM;
    if let Some(t) = title {
        ev.set("TITLE", t);
    }
    ev.set("APPLICATION", "nemoalarms");
    ev.set("createdDate", created_ms.to_string());
    ev
}

/// A countdown as Clock creates one: fires at `now + seconds`.
pub fn timer_event(now: i64, seconds: u32, label: Option<&str>) -> Result<EventIo, AdapterError> {
    let mut ev = base(label, now * 1000);
    let trigger = now + i64::from(seconds);
    ev.ticker = ticker(trigger)?;
    ev.set("timeOfDayWithSeconds", seconds.to_string());
    ev.set("triggerTime", trigger.to_string());
    ev.set("type", "countdown");
    Ok(ev)
}

/// A one-off clock alarm as Clock creates one: a daily recurrence at
/// `hour:minute` with the single-shot flag, which timed clears after the
/// first trigger.
pub fn alarm_event(now: i64, hour: u32, minute: u32, label: Option<&str>) -> EventIo {
    let mut ev = base(label, now * 1000);
    ev.flags |= flags::BOOT | flags::SINGLE_SHOT;
    ev.set(
        "timeOfDayWithSeconds",
        (hour * 3600 + minute * 60).to_string(),
    );
    ev.set("type", "clock");
    ev.recrs.push(Recurrence {
        mins: 1u64 << minute,
        hour: 1u32 << hour,
        mday: 0xFFFF_FFFF,
        wday: 0o177,
        mons: 0o7777,
        flags: 0,
    });
    ev
}

/// The application name on Pilot's reminders. timed takes
/// `[A-Za-z_][A-Za-z_0-9]*` only and refuses the event otherwise, so no
/// hyphen.
pub const REMINDER_APPLICATION: &str = "shoal_pilot";

/// A reminder: a one-off alarm at a fixed time with Pilot's title. Not a
/// Clock alarm (no `type`), so Clock's list does not show it; the alarm
/// dialog does.
pub fn reminder_event(now: i64, title: &str, at: i64) -> Result<EventIo, AdapterError> {
    let mut ev = base(Some(title), now * 1000);
    ev.flags |= flags::BOOT;
    ev.set("APPLICATION", REMINDER_APPLICATION);
    ev.ticker = ticker(at)?;
    Ok(ev)
}

/// Unix time of the next local `hour:minute` (today if still ahead, else
/// tomorrow), `day_offset` days later, by the clock on that day (a DST
/// change in between moves it with the clock).
pub fn next_local(now: &LocalNow, hour: u32, minute: u32, day_offset: u32) -> i64 {
    let t = now.local_time(i64::from(day_offset), hour, minute);
    if day_offset == 0 && t <= now.epoch {
        return now.local_time(1, hour, minute);
    }
    t
}

pub struct TimedClock {
    pub system: zbus::Connection,
}

impl TimedClock {
    async fn call<B, R>(&self, method: &str, body: &B) -> Result<R, AdapterError>
    where
        B: serde::Serialize + zbus::zvariant::DynamicType,
        R: for<'d> serde::Deserialize<'d> + zbus::zvariant::Type,
    {
        let reply = self
            .system
            .call_method(
                Some(TIMED_SERVICE),
                TIMED_PATH,
                Some(TIMED_INTERFACE),
                method,
                body,
            )
            .await?;
        Ok(reply.body().deserialize()?)
    }

    async fn add(&self, ev: &EventIo) -> Result<u32, AdapterError> {
        let reply = self
            .system
            .call_method(
                Some(TIMED_SERVICE),
                TIMED_PATH,
                Some(TIMED_INTERFACE),
                "add_event",
                &(ev,),
            )
            .await?;
        let cookie: u32 = reply.body().deserialize()?;
        if cookie == 0 {
            return Err(AdapterError::Failed("timed refused the event".into()));
        }
        Ok(cookie)
    }
}

fn now_epoch() -> i64 {
    crate::store::now_ms() / 1000
}

#[async_trait]
impl Clock for TimedClock {
    async fn set_timer(&self, seconds: u32, label: Option<&str>) -> Result<u32, AdapterError> {
        self.add(&timer_event(now_epoch(), seconds, label)?).await
    }

    async fn set_alarm(
        &self,
        hour: u32,
        minute: u32,
        label: Option<&str>,
    ) -> Result<u32, AdapterError> {
        self.add(&alarm_event(now_epoch(), hour, minute, label))
            .await
    }

    async fn create_reminder(&self, title: &str, at: i64) -> Result<u32, AdapterError> {
        self.add(&reminder_event(now_epoch(), title, at)?).await
    }

    async fn upcoming(&self) -> Result<Vec<ClockItem>, AdapterError> {
        let mut cookies: Vec<u32> = Vec::new();
        for app in ["nemoalarms", REMINDER_APPLICATION] {
            let attrs: HashMap<&str, &str> = HashMap::from([("APPLICATION", app)]);
            let found: Vec<u32> = self.call("get_cookies_by_attributes", &(attrs,)).await?;
            cookies.extend(found);
        }
        if cookies.is_empty() {
            return Ok(Vec::new());
        }
        let attrs: HashMap<u32, HashMap<String, String>> =
            self.call("get_attributes_by_cookies", &(cookies,)).await?;
        // Only events that will ring have a trigger (a switched-off alarm
        // has none).
        let triggers: HashMap<u32, u32> = self.call("get_alarm_triggers", &()).await?;
        Ok(upcoming_items(&attrs, &triggers))
    }

    async fn cancel(&self, cookie: u32) -> Result<bool, AdapterError> {
        self.call("cancel", &(cookie,)).await
    }
}

/// timed's events as [`ClockItem`]s, soonest first.
pub fn upcoming_items<S: std::hash::BuildHasher, T: std::hash::BuildHasher>(
    attrs: &HashMap<u32, HashMap<String, String, T>, S>,
    triggers: &HashMap<u32, u32, S>,
) -> Vec<ClockItem> {
    let mut items: Vec<ClockItem> = attrs
        .iter()
        .filter_map(|(cookie, a)| {
            let at = i64::from(*triggers.get(cookie)?);
            let get = |k: &str| a.get(k).cloned();
            let (kind, seconds, time) = match (get("APPLICATION")?.as_str(), get("type").as_deref())
            {
                ("nemoalarms", Some("countdown")) => (
                    "timer",
                    get("timeOfDayWithSeconds").and_then(|s| s.parse().ok()),
                    None,
                ),
                ("nemoalarms", Some("clock")) => {
                    let secs: u32 = get("timeOfDayWithSeconds")?.parse().ok()?;
                    (
                        "alarm",
                        None,
                        Some(format!("{:02}:{:02}", secs / 3600, secs % 3600 / 60)),
                    )
                }
                (REMINDER_APPLICATION, _) => ("reminder", None, None),
                _ => return None,
            };
            Some(ClockItem {
                cookie: *cookie,
                kind: kind.into(),
                title: get("TITLE").unwrap_or_default(),
                at,
                seconds,
                time,
            })
        })
        .collect();
    items.sort_by_key(|i| (i.at, i.cookie));
    items
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_signature_matches_timed() {
        assert_eq!(
            EventIo::SIGNATURE.to_string(),
            "(iuuuuus(a{ss})ua((a{ss})u)a(u(a{ss})a(sb))a(tuuuuu)iia(sb))"
        );
    }

    #[test]
    fn timer_like_clock_app() {
        let ev = timer_event(1_000, 300, Some("pasta")).unwrap();
        assert_eq!(ev.ticker, 1_300);
        assert_eq!(ev.attr.txt["type"], "countdown");
        assert_eq!(ev.attr.txt["TITLE"], "pasta");
        assert_eq!(ev.attr.txt["APPLICATION"], "nemoalarms");
        assert_eq!(ev.flags, flags::ALARM | flags::REMINDER | flags::KEEP_ALIVE);
        assert!(ev.recrs.is_empty());
    }

    #[test]
    fn upcoming_reads_timers_alarms_and_reminders() {
        let attrs = |pairs: &[(&str, &str)]| {
            pairs
                .iter()
                .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
                .collect::<HashMap<String, String>>()
        };
        let all = HashMap::from([
            (
                1,
                attrs(&[
                    ("APPLICATION", "nemoalarms"),
                    ("type", "countdown"),
                    ("TITLE", "tea"),
                    ("timeOfDayWithSeconds", "600"),
                ]),
            ),
            (
                2,
                attrs(&[
                    ("APPLICATION", "nemoalarms"),
                    ("type", "clock"),
                    ("TITLE", ""),
                    ("timeOfDayWithSeconds", "26100"),
                ]),
            ),
            (
                3,
                attrs(&[("APPLICATION", "shoal_pilot"), ("TITLE", "stretch")]),
            ),
            (
                4,
                attrs(&[
                    ("APPLICATION", "nemoalarms"),
                    ("type", "clock"),
                    ("timeOfDayWithSeconds", "3600"),
                ]),
            ),
        ]);
        // 4 is switched off: no trigger.
        let triggers = HashMap::from([(1, 500), (2, 900), (3, 700)]);
        let items = upcoming_items(&all, &triggers);
        let kinds: Vec<(&str, i64)> = items.iter().map(|i| (i.kind.as_str(), i.at)).collect();
        assert_eq!(kinds, [("timer", 500), ("reminder", 700), ("alarm", 900)]);
        assert_eq!(items[0].seconds, Some(600));
        assert_eq!(items[2].time.as_deref(), Some("07:15"));
        assert_eq!(items[1].title, "stretch");
    }

    #[test]
    fn application_names_pass_timeds_check() {
        // timed: `^[A-Za-z_][A-Za-z_0-9]*$`, else "invalid application name".
        let ok = |n: &str| {
            n.chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        };
        let events = [
            timer_event(1_000, 60, None).unwrap(),
            alarm_event(1_000, 7, 30, None),
            reminder_event(1_000, "stretch", 2_000).unwrap(),
        ];
        for ev in &events {
            assert!(
                ok(&ev.attr.txt["APPLICATION"]),
                "{}",
                ev.attr.txt["APPLICATION"]
            );
        }
        assert_eq!(events[2].attr.txt["APPLICATION"], REMINDER_APPLICATION);
    }

    #[test]
    fn alarm_recurrence_masks() {
        let ev = alarm_event(0, 7, 30, None);
        let r = &ev.recrs[0];
        assert_eq!(r.hour, 1 << 7);
        assert_eq!(r.mins, 1 << 30);
        assert_eq!(r.wday, 0b111_1111);
        assert_ne!(ev.flags & flags::SINGLE_SHOT, 0);
        assert_eq!(ev.attr.txt["timeOfDayWithSeconds"], "27000");
        assert_eq!(ev.ticker, 0);
    }

    #[test]
    fn next_local_rolls_over() {
        let now = LocalNow::fixed_utc(1_790_966_550); // 18:42:30
        let mid = now.midnight();
        assert_eq!(next_local(&now, 19, 0, 0), mid + 19 * 3600);
        assert_eq!(next_local(&now, 7, 0, 0), mid + 86_400 + 7 * 3600);
        assert_eq!(next_local(&now, 7, 0, 1), mid + 86_400 + 7 * 3600);
    }
}
