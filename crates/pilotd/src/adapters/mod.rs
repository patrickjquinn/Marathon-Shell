// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Thin adapters over Sailfish services (spec section 14: "thin adapter
//! layer per service; test against each OS release"). Each is a trait the
//! pipeline and the system tools use, with one Sailfish implementation and
//! fakes in tests.

pub mod calendar;
pub mod clock;
pub mod connman;
pub mod contacts;
pub mod media;
pub mod stock;
pub mod telephony;
pub mod voice;

use async_trait::async_trait;
use serde::Serialize;

use crate::intents::{DayRange, MediaAction};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AdapterError {
    /// The service is not present or not wired in this build.
    #[error("{0} is not available on this device")]
    Unavailable(String),
    #[error("{0}")]
    Failed(String),
}

impl From<zbus::Error> for AdapterError {
    fn from(e: zbus::Error) -> Self {
        AdapterError::Failed(e.to_string())
    }
}

impl From<zbus::fdo::Error> for AdapterError {
    fn from(e: zbus::fdo::Error) -> Self {
        AdapterError::Failed(e.to_string())
    }
}

/// Timers, alarms and reminders (timed, as the Clock app uses it).
#[async_trait]
pub trait Clock: Send + Sync {
    /// Returns timed's cookie.
    async fn set_timer(&self, seconds: u32, label: Option<&str>) -> Result<u32, AdapterError>;
    /// The next occurrence of `hour:minute`, local time.
    async fn set_alarm(
        &self,
        hour: u32,
        minute: u32,
        label: Option<&str>,
    ) -> Result<u32, AdapterError>;
    /// A one-off reminder at Unix time `at`.
    async fn create_reminder(&self, title: &str, at: i64) -> Result<u32, AdapterError>;
    /// What is set and will still ring: Clock's timers and alarms and
    /// Pilot's reminders, soonest first.
    async fn upcoming(&self) -> Result<Vec<ClockItem>, AdapterError> {
        Ok(Vec::new())
    }
    /// Cancels the event `cookie`; `false` when timed had no such event.
    async fn cancel(&self, _cookie: u32) -> Result<bool, AdapterError> {
        Err(AdapterError::Unavailable("timed".into()))
    }
}

/// One timer, alarm or reminder that will ring.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ClockItem {
    pub cookie: u32,
    /// "timer", "alarm" or "reminder".
    pub kind: String,
    pub title: String,
    /// When it rings, Unix seconds.
    pub at: i64,
    /// A timer's length; an alarm's time of day ("07:15").
    pub seconds: Option<u32>,
    pub time: Option<String>,
}

/// MPRIS players.
#[async_trait]
pub trait Media: Send + Sync {
    /// Returns the player that was controlled.
    async fn control(&self, action: MediaAction) -> Result<String, AdapterError>;
}

#[derive(Debug, Clone, PartialEq, Serialize, serde::Deserialize)]
pub struct CalendarEvent {
    pub title: String,
    /// Unix seconds.
    pub start: i64,
    pub end: i64,
    pub all_day: bool,
    pub location: Option<String>,
}

/// The calendar (mkcal).
pub trait Calendar: Send + Sync {
    /// Events overlapping `[from, to)`, earliest first.
    fn events(&self, from: i64, to: i64, limit: usize) -> Result<Vec<CalendarEvent>, AdapterError>;

    /// A value that changes whenever the calendar may have, so a poller can
    /// skip reading an unchanged calendar. `None`: unknown, read every time.
    fn stamp(&self) -> Option<u64> {
        None
    }
}

/// The Unix-second window for a day range, from local `now`.
/// Days start at local midnight by the zone's rules (a day with a DST
/// change is 23 or 25 hours long).
pub fn range_window(range: DayRange, now: &crate::localtime::LocalNow) -> (i64, i64) {
    let day = |n: i64| now.local_time(n, 0, 0);
    match range {
        DayRange::Today => (now.epoch, day(1)),
        DayRange::Tomorrow => (day(1), day(2)),
        DayRange::Week => (now.epoch, day(8)),
        DayRange::Next => (now.epoch, now.epoch + 366 * 86_400),
        DayRange::Weekday(d) => match (d + 7 - now.weekday) % 7 {
            0 => (now.epoch, day(1)),
            n => (day(i64::from(n)), day(i64::from(n) + 1)),
        },
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Contact {
    pub name: String,
    pub phones: Vec<String>,
    pub emails: Vec<String>,
}

/// The address book (qtcontacts-sqlite). Also the redactor's name source.
pub trait Contacts: Send + Sync {
    fn names(&self) -> Vec<String>;
    fn lookup(&self, query: &str, limit: usize) -> Result<Vec<Contact>, AdapterError>;
}

/// Calls and SMS.
#[async_trait]
pub trait Telephony: Send + Sync {
    async fn dial(&self, number: &str) -> Result<(), AdapterError>;
    async fn send_sms(&self, to: &str, text: &str) -> Result<(), AdapterError>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Toggle {
    Wifi,
    Bluetooth,
    MobileData,
    FlightMode,
}

impl Toggle {
    pub fn parse(s: &str) -> Option<Toggle> {
        Some(match s {
            "wifi" => Toggle::Wifi,
            "bluetooth" => Toggle::Bluetooth,
            "mobile_data" => Toggle::MobileData,
            "flight_mode" => Toggle::FlightMode,
            _ => return None,
        })
    }
}

/// Radios and flight mode (ConnMan).
#[async_trait]
pub trait DeviceToggles: Send + Sync {
    async fn set(&self, what: Toggle, on: bool) -> Result<(), AdapterError>;
    /// Whether it is on now.
    async fn get(&self, what: Toggle) -> Result<bool, AdapterError>;
}

/// `pilot-voice`: one push-to-talk turn, and stopping the process (the
/// privacy switch closes the microphone path that way).
#[async_trait]
pub trait VoiceControl: Send + Sync {
    /// Records and transcribes one utterance; empty when nobody spoke.
    async fn listen(&self) -> Result<String, AdapterError>;
    /// [`listen`](Self::listen), telling `report` what happens meanwhile:
    /// `("listening", 0)`, `("level", 0..1)` about 16 times a second,
    /// `("transcribing", 0)`.
    async fn listen_reporting(
        &self,
        report: &(dyn Fn(&str, f64) + Send + Sync),
    ) -> Result<String, AdapterError> {
        report("listening", 0.0);
        self.listen().await
    }
    async fn stop(&self) -> Result<(), AdapterError>;
}

/// `pilot-tts`: speaks a response. Fire and forget; never blocks a turn.
pub trait Speech: Send + Sync {
    fn say(&self, text: &str);
    fn stop(&self);
}

/// The home screen's notifications (`org.freedesktop.Notifications`,
/// Lipstick on Sailfish): Pilot's entry in the Events view.
#[async_trait]
pub trait Notifier: Send + Sync {
    /// Shows or, with `replaces` non-zero, updates a notification; returns
    /// its id. `hints` are string-valued.
    async fn show(
        &self,
        replaces: u32,
        summary: &str,
        body: &str,
        hints: &[(&str, String)],
    ) -> Result<u32, AdapterError>;
    async fn close(&self, id: u32) -> Result<(), AdapterError>;
}

/// `org.freedesktop.Notifications` on the session bus.
pub struct FdoNotifier {
    pub session: zbus::Connection,
}

#[async_trait]
impl Notifier for FdoNotifier {
    async fn show(
        &self,
        replaces: u32,
        summary: &str,
        body: &str,
        hints: &[(&str, String)],
    ) -> Result<u32, AdapterError> {
        let hints: std::collections::HashMap<&str, zbus::zvariant::Value<'_>> = hints
            .iter()
            .map(|(k, v)| (*k, zbus::zvariant::Value::from(v.as_str())))
            .collect();
        let reply = self
            .session
            .call_method(
                Some("org.freedesktop.Notifications"),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                "Notify",
                &(
                    "Pilot",
                    replaces,
                    "",
                    summary,
                    body,
                    Vec::<&str>::new(),
                    hints,
                    -1i32,
                ),
            )
            .await?;
        Ok(reply.body().deserialize::<u32>()?)
    }

    async fn close(&self, id: u32) -> Result<(), AdapterError> {
        self.session
            .call_method(
                Some("org.freedesktop.Notifications"),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                "CloseNotification",
                &(id,),
            )
            .await?;
        Ok(())
    }
}

/// Everything the handlers and system tools need.
pub struct Adapters {
    pub clock: Box<dyn Clock>,
    pub media: Box<dyn Media>,
    pub calendar: Box<dyn Calendar>,
    pub contacts: std::sync::Arc<dyn Contacts>,
    pub telephony: Box<dyn Telephony>,
    pub toggles: Box<dyn DeviceToggles>,
    pub voice: Box<dyn VoiceControl>,
    pub speech: Box<dyn Speech>,
    pub notifier: Box<dyn Notifier>,
    /// Sailfish's own apps, through their D-Bus entry points.
    pub stock: Box<dyn stock::StockApps>,
}

/// An adapter for a service this build does not have.
pub struct Missing(pub &'static str);

#[async_trait]
impl Clock for Missing {
    async fn set_timer(&self, _: u32, _: Option<&str>) -> Result<u32, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn set_alarm(&self, _: u32, _: u32, _: Option<&str>) -> Result<u32, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn create_reminder(&self, _: &str, _: i64) -> Result<u32, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

#[async_trait]
impl Media for Missing {
    async fn control(&self, _: MediaAction) -> Result<String, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

impl Calendar for Missing {
    fn events(&self, _: i64, _: i64, _: usize) -> Result<Vec<CalendarEvent>, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

impl Contacts for Missing {
    fn names(&self) -> Vec<String> {
        Vec::new()
    }
    fn lookup(&self, _: &str, _: usize) -> Result<Vec<Contact>, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

#[async_trait]
impl stock::StockApps for Missing {
    async fn compose_email(&self, _: &str, _: &str, _: &str) -> Result<bool, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn new_note(&self, _: &str) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn open_settings(&self, _: &str) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn compose_sms(&self, _: &str, _: &str) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

#[async_trait]
impl Telephony for Missing {
    async fn dial(&self, _: &str) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn send_sms(&self, _: &str, _: &str) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

#[async_trait]
impl DeviceToggles for Missing {
    async fn set(&self, _: Toggle, _: bool) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn get(&self, _: Toggle) -> Result<bool, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
}

#[async_trait]
impl VoiceControl for Missing {
    async fn listen(&self) -> Result<String, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn stop(&self) -> Result<(), AdapterError> {
        Ok(())
    }
}

#[async_trait]
impl Notifier for Missing {
    async fn show(
        &self,
        _: u32,
        _: &str,
        _: &str,
        _: &[(&str, String)],
    ) -> Result<u32, AdapterError> {
        Err(AdapterError::Unavailable(self.0.into()))
    }
    async fn close(&self, _: u32) -> Result<(), AdapterError> {
        Ok(())
    }
}

impl Speech for Missing {
    fn say(&self, _: &str) {}
    fn stop(&self) {}
}

/// Bridges an address book to the redactor's name source.
pub struct NamesFrom(pub std::sync::Arc<dyn Contacts>);

impl crate::redact::ContactNames for NamesFrom {
    fn names(&self) -> Vec<String> {
        self.0.names()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::localtime::LocalNow;

    #[test]
    fn windows() {
        let now = LocalNow::fixed_utc(1_790_966_550); // Fri 18:42:30 UTC
        let mid = now.midnight();
        assert_eq!(
            range_window(DayRange::Today, &now),
            (now.epoch, mid + 86_400)
        );
        assert_eq!(
            range_window(DayRange::Tomorrow, &now),
            (mid + 86_400, mid + 172_800)
        );
        // A Friday: Monday is three days on, Friday itself is today.
        assert_eq!(
            range_window(DayRange::Weekday(1), &now),
            (mid + 3 * 86_400, mid + 4 * 86_400)
        );
        assert_eq!(
            range_window(DayRange::Weekday(5), &now),
            (now.epoch, mid + 86_400)
        );
    }
}
