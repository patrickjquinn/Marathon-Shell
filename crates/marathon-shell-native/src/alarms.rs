//! `Alarms`: the clock's alarms and timers, and the ones ringing. The book
//! of alarms is kept as JSON in `data`, which the shell stores in its
//! settings. A timer on the I/O thread wakes the shell for the next one; it
//! stands still in suspend, so the shell checks again on resume.

use std::pin::Pin;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use serde::{Deserialize, Serialize};
use tz::{DateTime, TimeZone, TimeZoneRef, UtcDateTime};
use zbus::fdo;
use zbus::message::Header;
use zbus::zvariant::{OwnedValue, Value};

use crate::ipc::{self, value, State};
use crate::{io, log, variant};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        type QList_i32 = cxx_qt_lib::QList<i32>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        /// The alarms the clock shows: not snoozes or timers.
        #[qproperty(QList_QVariant, alarms, READ, NOTIFY)]
        #[qproperty(bool, has_enabled_alarm, cxx_name = "hasEnabledAlarm", READ, NOTIFY = alarms_changed)]
        #[qproperty(QList_QVariant, active_alarms, cxx_name = "activeAlarms", READ, NOTIFY)]
        #[qproperty(bool, has_active_alarm, cxx_name = "hasActiveAlarm", READ, NOTIFY = active_alarms_changed)]
        /// Every alarm, as JSON.
        #[qproperty(QString, data, READ, WRITE = set_data, NOTIFY)]
        type Alarms = super::AlarmsRust;

        #[cxx_name = "setData"]
        fn set_data(self: Pin<&mut Alarms>, data: &QString);

        #[qsignal]
        #[cxx_name = "alarmTriggered"]
        fn alarm_triggered(self: Pin<&mut Self>, id: &QString, label: &QString);
        #[qsignal]
        #[cxx_name = "alarmDismissed"]
        fn alarm_dismissed(self: Pin<&mut Self>, id: &QString);
        #[qsignal]
        #[cxx_name = "alarmSnoozed"]
        fn alarm_snoozed(self: Pin<&mut Self>, id: &QString, minutes: i32);
        /// Seconds since the epoch, 0 when no alarm is set.
        #[qsignal]
        #[cxx_name = "nextAlarmScheduled"]
        fn next_alarm_scheduled(self: Pin<&mut Self>, epoch_secs: i64);
        /// An alarm started ringing: play its sound, buzz, keep awake.
        #[qsignal]
        fn ringing(self: Pin<&mut Self>, sound: bool, vibrate: bool);
        /// Nothing rings any more.
        #[qsignal]
        fn silenced(self: Pin<&mut Self>);

        /// `options`: sound, vibrate, snoozeEnabled, snoozeDuration, and for
        /// a timer oneShot, hidden and `at` (ms since the epoch).
        #[qinvokable]
        #[cxx_name = "createAlarm"]
        fn create_alarm(
            self: Pin<&mut Alarms>,
            time: &QString,
            label: &QString,
            repeat: &QList_i32,
            options: &QMap_QString_QVariant,
        ) -> QString;
        #[qinvokable]
        #[cxx_name = "updateAlarm"]
        fn update_alarm(
            self: Pin<&mut Alarms>,
            id: &QString,
            updates: &QMap_QString_QVariant,
        ) -> bool;
        #[qinvokable]
        #[cxx_name = "deleteAlarm"]
        fn delete_alarm(self: Pin<&mut Alarms>, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "enableAlarm"]
        fn enable_alarm(self: Pin<&mut Alarms>, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "disableAlarm"]
        fn disable_alarm(self: Pin<&mut Alarms>, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "snoozeAlarm"]
        fn snooze_alarm(self: Pin<&mut Alarms>, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "dismissAlarm"]
        fn dismiss_alarm(self: Pin<&mut Alarms>, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "stopAll"]
        fn stop_all(self: Pin<&mut Alarms>);
        #[qinvokable]
        #[cxx_name = "triggerAlarmNow"]
        fn trigger_alarm_now(self: Pin<&mut Alarms>, label: &QString);
        /// Rings what is due; after a resume, before anything asks
        /// whether an alarm rings.
        #[qinvokable]
        #[cxx_name = "checkAlarms"]
        fn check_alarms(self: Pin<&mut Alarms>);
    }

    impl cxx_qt::Threading for Alarms {}
    impl cxx_qt::Initialize for Alarms {}
}

use qobject::Alarms;

#[derive(Default)]
pub struct AlarmsRust {
    alarms: QList<QVariant>,
    has_enabled_alarm: bool,
    active_alarms: QList<QVariant>,
    has_active_alarm: bool,
    data: QString,
    book: Book,
    active: Vec<Alarm>,
    zone: Option<TimeZone>,
    timer: Option<Sender<Option<Duration>>>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
#[allow(clippy::struct_excessive_bools, reason = "the stored alarm's fields")]
struct Alarm {
    id: String,
    time: String,
    enabled: bool,
    label: String,
    /// Days of the week, Sunday 0.
    repeat: Vec<i32>,
    sound: String,
    vibrate: bool,
    snooze_enabled: bool,
    snooze_duration: i32,
    /// A one-shot rings once at `at`, ms since the epoch, and is removed.
    #[serde(skip_serializing_if = "is_zero")]
    at: i64,
    #[serde(skip_serializing_if = "is_false")]
    one_shot: bool,
    #[serde(skip_serializing_if = "is_false")]
    hidden: bool,
}

#[allow(
    clippy::trivially_copy_pass_by_ref,
    reason = "serde's skip_serializing_if"
)]
const fn is_zero(v: &i64) -> bool {
    *v == 0
}

#[allow(
    clippy::trivially_copy_pass_by_ref,
    reason = "serde's skip_serializing_if"
)]
const fn is_false(v: &bool) -> bool {
    !*v
}

impl Default for Alarm {
    fn default() -> Self {
        Self {
            id: String::new(),
            time: String::new(),
            enabled: false,
            label: String::new(),
            repeat: Vec::new(),
            sound: String::new(),
            vibrate: false,
            snooze_enabled: false,
            snooze_duration: 10,
            at: 0,
            one_shot: false,
            hidden: false,
        }
    }
}

impl Alarm {
    /// Its next ring after `from`, in ms.
    fn next(&self, from: i64, zone: TimeZoneRef<'_>) -> Option<i64> {
        if self.one_shot {
            return Some(self.at);
        }
        let (h, m) = self.time.split_once(':')?;
        let (h, m): (u8, u8) = (h.trim().parse().ok()?, m.trim().parse().ok()?);
        let local = DateTime::from_timespec(from.div_euclid(1000), 0, zone).ok()?;
        let midnight = UtcDateTime::new(local.year(), local.month(), local.month_day(), 0, 0, 0, 0)
            .ok()?
            .unix_time();
        for day in 0..8 {
            let date = UtcDateTime::from_timespec(midnight + day * 86_400, 0).ok()?;
            let Some(at) = DateTime::find(
                date.year(),
                date.month(),
                date.month_day(),
                h,
                m,
                0,
                0,
                zone,
            )
            .ok()
            .and_then(|f| f.earliest()) else {
                continue;
            };
            let ms = at.unix_time() * 1000;
            if ms > from
                && (self.repeat.is_empty() || self.repeat.contains(&i32::from(at.week_day())))
            {
                return Some(ms);
            }
        }
        None
    }

    fn to_map(&self) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        let mut text =
            |k: &str, v: &str| map.insert(QString::from(k), QVariant::from(&QString::from(v)));
        text("id", &self.id);
        text("time", &self.time);
        text("label", &self.label);
        text("sound", &self.sound);
        let mut repeat = QList::<QVariant>::default();
        for day in &self.repeat {
            repeat.append(QVariant::from(day));
        }
        map.insert(QString::from("repeat"), QVariant::from(&repeat));
        map.insert(QString::from("enabled"), QVariant::from(&self.enabled));
        map.insert(QString::from("vibrate"), QVariant::from(&self.vibrate));
        map.insert(
            QString::from("snoozeEnabled"),
            QVariant::from(&self.snooze_enabled),
        );
        map.insert(
            QString::from("snoozeDuration"),
            QVariant::from(&self.snooze_duration),
        );
        if self.one_shot {
            map.insert(QString::from("at"), QVariant::from(&self.at));
            map.insert(QString::from("oneShot"), QVariant::from(&true));
        }
        if self.hidden {
            map.insert(QString::from("hidden"), QVariant::from(&true));
        }
        map
    }

    fn to_state(&self) -> State {
        let mut state = State::from([
            ("id".to_owned(), value(self.id.clone())),
            ("time".to_owned(), value(self.time.clone())),
            ("label".to_owned(), value(self.label.clone())),
            ("sound".to_owned(), value(self.sound.clone())),
            ("repeat".to_owned(), value(self.repeat.clone())),
            ("enabled".to_owned(), value(self.enabled)),
            ("vibrate".to_owned(), value(self.vibrate)),
            ("snoozeEnabled".to_owned(), value(self.snooze_enabled)),
            ("snoozeDuration".to_owned(), value(self.snooze_duration)),
        ]);
        if self.one_shot {
            state.insert("at".to_owned(), value(self.at));
            state.insert("oneShot".to_owned(), value(true));
        }
        if self.hidden {
            state.insert("hidden".to_owned(), value(true));
        }
        state
    }

    fn apply(&mut self, c: &Changes) {
        let Changes {
            time,
            label,
            sound,
            enabled,
            vibrate,
            snooze_enabled,
            snooze_duration,
            repeat,
            ..
        } = c.clone();
        self.time = time.unwrap_or_else(|| std::mem::take(&mut self.time));
        self.label = label.unwrap_or_else(|| std::mem::take(&mut self.label));
        self.sound = sound.unwrap_or_else(|| std::mem::take(&mut self.sound));
        self.enabled = enabled.unwrap_or(self.enabled);
        self.vibrate = vibrate.unwrap_or(self.vibrate);
        self.snooze_enabled = snooze_enabled.unwrap_or(self.snooze_enabled);
        self.snooze_duration = snooze_duration.unwrap_or(self.snooze_duration);
        self.repeat = repeat.unwrap_or_else(|| std::mem::take(&mut self.repeat));
    }
}

/// The fields a caller's options set, from QML or D-Bus.
#[derive(Clone, Default)]
struct Changes {
    time: Option<String>,
    label: Option<String>,
    sound: Option<String>,
    enabled: Option<bool>,
    vibrate: Option<bool>,
    snooze_enabled: Option<bool>,
    snooze_duration: Option<i32>,
    repeat: Option<Vec<i32>>,
    one_shot: Option<bool>,
    hidden: Option<bool>,
    at: Option<i64>,
}

impl Changes {
    fn from_qt(options: &QMap<QMapPair_QString_QVariant>) -> Self {
        let get = |k: &str| options.get(&QString::from(k));
        let text = |k: &str| {
            get(k)
                .and_then(|v| v.value::<QString>())
                .map(|v| v.to_string())
        };
        let flag = |k: &str| get(k).and_then(|v| v.value::<bool>());
        Self {
            time: text("time"),
            label: text("label"),
            sound: text("sound"),
            enabled: flag("enabled"),
            vibrate: flag("vibrate"),
            snooze_enabled: flag("snoozeEnabled"),
            snooze_duration: get("snoozeDuration").and_then(|v| v.value::<i32>()),
            repeat: get("repeat")
                .and_then(|v| v.value::<QList<QVariant>>())
                .map(|v| v.iter().filter_map(QVariant::value::<i32>).collect()),
            one_shot: flag("oneShot"),
            hidden: flag("hidden"),
            at: get("at").and_then(|v| v.value::<i64>()),
        }
    }

    fn from_dbus(options: &State) -> Self {
        let get = |k: &str| {
            options.get(k).map(|v| match &**v {
                Value::Value(inner) => inner.as_ref(),
                v => v,
            })
        };
        let text = |k: &str| match get(k) {
            Some(Value::Str(s)) => Some(s.to_string()),
            _ => None,
        };
        let flag = |k: &str| match get(k) {
            Some(Value::Bool(b)) => Some(*b),
            _ => None,
        };
        let int = |k: &str| get(k).and_then(variant::number);
        Self {
            time: text("time"),
            label: text("label"),
            sound: text("sound"),
            enabled: flag("enabled"),
            vibrate: flag("vibrate"),
            snooze_enabled: flag("snoozeEnabled"),
            snooze_duration: int("snoozeDuration").and_then(|n| i32::try_from(n).ok()),
            repeat: match get("repeat") {
                Some(Value::Array(days)) => Some(
                    days.iter()
                        .filter_map(variant::number)
                        .filter_map(|n| i32::try_from(n).ok())
                        .collect(),
                ),
                _ => None,
            },
            one_shot: flag("oneShot"),
            hidden: flag("hidden"),
            at: int("at"),
        }
    }
}

/// Every alarm, and when the last rang, so a timer firing early can't ring
/// it twice.
#[derive(Default)]
struct Book {
    alarms: Vec<Alarm>,
    last_fired: i64,
    /// Where the last schedule counted from; 0 before the first.
    from: i64,
    made: u64,
}

impl Book {
    fn new_id(&mut self, now: i64) -> String {
        self.made += 1;
        format!("{now:x}{:x}", self.made)
    }

    /// The next ring of any alarm, counting from now or the last ring.
    fn schedule(&mut self, now: i64, zone: TimeZoneRef<'_>) -> Option<i64> {
        self.from = self.last_fired.max(now);
        self.alarms
            .iter()
            .filter(|a| a.enabled)
            .filter_map(|a| a.next(self.from, zone))
            .min()
    }

    /// What is due by `now`: one-offs switch off, one-shots go.
    fn due(&mut self, now: i64, zone: TimeZoneRef<'_>) -> Vec<Alarm> {
        if self.from == 0 {
            return Vec::new();
        }
        // Timers may fire marginally early.
        let horizon = now + 50;
        let (from, mut last) = (self.from, self.last_fired);
        let mut due = Vec::new();
        self.alarms.retain_mut(|a| {
            let Some(at) = a.next(from, zone).filter(|at| a.enabled && *at <= horizon) else {
                return true;
            };
            due.push(a.clone());
            last = last.max(at);
            if a.one_shot {
                return false;
            }
            if a.repeat.is_empty() {
                a.enabled = false;
            }
            true
        });
        self.last_fired = last;
        due
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
}

fn hh_mm(ms: i64, zone: TimeZoneRef<'_>) -> String {
    DateTime::from_timespec(ms.div_euclid(1000), 0, zone).map_or_else(
        |_| String::new(),
        |t| format!("{:02}:{:02}", t.hour(), t.minute()),
    )
}

impl cxx_qt::Initialize for Alarms {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(16);
        io::spawn(timer(self.qt_thread(), rx));
        self.as_mut().rust_mut().timer = Some(tx);
        self.as_mut()
            .on_alarms_changed(|_| ipc::signal("Alarm", "AlarmsChanged", ()))
            .release();
        self.as_mut()
            .on_active_alarms_changed(|_| ipc::signal("Alarm", "ActiveAlarmsChanged", ()))
            .release();
        self.as_mut()
            .on_alarm_triggered(|_, id, label| {
                ipc::signal(
                    "Alarm",
                    "AlarmTriggered",
                    (id.to_string(), label.to_string()),
                );
            })
            .release();
        self.as_mut()
            .on_alarm_dismissed(|_, id| ipc::signal("Alarm", "AlarmDismissed", (id.to_string(),)))
            .release();
        self.as_mut()
            .on_alarm_snoozed(|_, id, minutes| {
                ipc::signal("Alarm", "AlarmSnoozed", (id.to_string(), minutes));
            })
            .release();
        ipc::export(
            "Alarm",
            Alarm1 {
                qt: self.qt_thread(),
            },
        );
    }
}

impl Alarms {
    fn zone(&self) -> TimeZoneRef<'_> {
        self.zone
            .as_ref()
            .map_or_else(TimeZoneRef::utc, TimeZone::as_ref)
    }

    fn set_data(mut self: Pin<&mut Self>, data: &QString) {
        let alarms = serde_json::from_str(&data.to_string()).unwrap_or_else(|e| {
            log::warn("alarms", format_args!("unreadable alarms: {e}"));
            Vec::new()
        });
        let mut rust = self.as_mut().rust_mut();
        rust.data = data.clone();
        rust.book.alarms = alarms;
        self.as_mut().publish();
        self.schedule();
    }

    /// Stores, shows and schedules the book after a change.
    fn changed(mut self: Pin<&mut Self>, shown: bool) {
        match serde_json::to_string(&self.book.alarms) {
            Ok(json) => {
                self.as_mut().rust_mut().data = QString::from(json.as_str());
                self.as_mut().data_changed();
            }
            Err(e) => log::warn("alarms", e),
        }
        if shown {
            self.as_mut().publish();
        }
        self.schedule();
    }

    fn publish(mut self: Pin<&mut Self>) {
        let mut list = QList::<QVariant>::default();
        for a in self.book.alarms.iter().filter(|a| !a.hidden) {
            list.append(QVariant::from(&a.to_map()));
        }
        let enabled = self.book.alarms.iter().any(|a| a.enabled && !a.hidden);
        let mut rust = self.as_mut().rust_mut();
        rust.alarms = list;
        rust.has_enabled_alarm = enabled;
        self.alarms_changed();
    }

    fn publish_active(mut self: Pin<&mut Self>) {
        let mut list = QList::<QVariant>::default();
        for a in &self.active {
            list.append(QVariant::from(&a.to_map()));
        }
        let mut rust = self.as_mut().rust_mut();
        rust.active_alarms = list;
        rust.has_active_alarm = !rust.active.is_empty();
        self.active_alarms_changed();
    }

    fn schedule(mut self: Pin<&mut Self>) {
        let now = now_ms();
        let zone = self.zone.clone();
        let next = self.as_mut().rust_mut().book.schedule(
            now,
            zone.as_ref()
                .map_or_else(TimeZoneRef::utc, TimeZone::as_ref),
        );
        self.as_mut()
            .next_alarm_scheduled(next.map_or(0, |at| at.div_euclid(1000)));
        if let Some(timer) = &self.timer {
            let wait = next.map(|at| Duration::from_millis(u64::try_from(at - now).unwrap_or(0)));
            timer.try_send(wait).ok();
        }
    }

    fn create_alarm(
        self: Pin<&mut Self>,
        time: &QString,
        label: &QString,
        repeat: &QList<i32>,
        options: &QMap<QMapPair_QString_QVariant>,
    ) -> QString {
        QString::from(&self.create(
            time.to_string(),
            label.to_string(),
            repeat.iter().copied().collect(),
            &Changes::from_qt(options),
        ))
    }

    fn create(
        mut self: Pin<&mut Self>,
        time: String,
        label: String,
        repeat: Vec<i32>,
        options: &Changes,
    ) -> String {
        let now = now_ms();
        let mut alarm = Alarm {
            time,
            label: if label.is_empty() {
                "Alarm".to_owned()
            } else {
                label
            },
            repeat,
            enabled: true,
            sound: "default".to_owned(),
            vibrate: true,
            snooze_enabled: true,
            one_shot: options.one_shot.unwrap_or(false),
            hidden: options.hidden.unwrap_or(false),
            ..Alarm::default()
        };
        alarm.apply(options);
        if alarm.one_shot {
            alarm.at = options.at.unwrap_or(0);
            if alarm.at <= 0 {
                return String::new();
            }
            alarm.time = hh_mm(alarm.at, self.zone());
            alarm.repeat.clear();
        }
        let id = self.as_mut().rust_mut().book.new_id(now);
        alarm.id.clone_from(&id);
        let shown = !alarm.hidden;
        self.as_mut().rust_mut().book.alarms.push(alarm);
        self.changed(shown);
        id
    }

    fn update_alarm(
        self: Pin<&mut Self>,
        id: &QString,
        updates: &QMap<QMapPair_QString_QVariant>,
    ) -> bool {
        self.update(&id.to_string(), &Changes::from_qt(updates))
    }

    fn update(mut self: Pin<&mut Self>, id: &str, changes: &Changes) -> bool {
        let mut rust = self.as_mut().rust_mut();
        let Some(alarm) = rust.book.alarms.iter_mut().find(|a| a.id == id) else {
            return false;
        };
        alarm.apply(changes);
        self.changed(true);
        true
    }

    fn set_enabled(self: Pin<&mut Self>, id: &QString, enabled: bool) -> bool {
        self.update(
            &id.to_string(),
            &Changes {
                enabled: Some(enabled),
                ..Changes::default()
            },
        )
    }

    fn enable_alarm(self: Pin<&mut Self>, id: &QString) -> bool {
        self.set_enabled(id, true)
    }

    fn disable_alarm(self: Pin<&mut Self>, id: &QString) -> bool {
        self.set_enabled(id, false)
    }

    fn delete_alarm(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let id = id.to_string();
        let mut rust = self.as_mut().rust_mut();
        let Some(i) = rust.book.alarms.iter().position(|a| a.id == id) else {
            return false;
        };
        let shown = !rust.book.alarms.remove(i).hidden;
        self.changed(shown);
        true
    }

    /// Takes `id` off the ringing list, silencing when it was the last.
    fn take_active(mut self: Pin<&mut Self>, id: &QString) -> Option<Alarm> {
        let id = id.to_string();
        let mut rust = self.as_mut().rust_mut();
        let i = rust.active.iter().position(|a| a.id == id)?;
        let alarm = rust.active.remove(i);
        self.as_mut().publish_active();
        if self.active.is_empty() {
            self.silenced();
        }
        Some(alarm)
    }

    fn snooze_alarm(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let Some(alarm) = self.as_mut().take_active(id) else {
            return false;
        };
        let (now, minutes) = (now_ms(), alarm.snooze_duration);
        let at = now + i64::from(minutes) * 60_000;
        let again = Alarm {
            id: self.as_mut().rust_mut().book.new_id(now),
            one_shot: true,
            hidden: true,
            enabled: true,
            repeat: Vec::new(),
            at,
            time: hh_mm(at, self.zone()),
            ..alarm
        };
        self.as_mut().rust_mut().book.alarms.push(again);
        self.as_mut().changed(false);
        self.alarm_snoozed(id, minutes);
        true
    }

    fn dismiss_alarm(mut self: Pin<&mut Self>, id: &QString) -> bool {
        if self.as_mut().take_active(id).is_none() {
            return false;
        }
        self.as_mut().alarm_dismissed(id);
        self.schedule();
        true
    }

    fn stop_all(self: Pin<&mut Self>) {
        self.silenced();
    }

    fn trigger_alarm_now(mut self: Pin<&mut Self>, label: &QString) {
        let now = now_ms();
        let alarm = Alarm {
            id: self.as_mut().rust_mut().book.new_id(now),
            time: hh_mm(now, self.zone()),
            label: if label.is_empty() {
                "Test Alarm".to_owned()
            } else {
                label.to_string()
            },
            enabled: true,
            sound: "default".to_owned(),
            vibrate: true,
            snooze_enabled: true,
            ..Alarm::default()
        };
        self.ring(alarm);
    }

    fn check_alarms(mut self: Pin<&mut Self>) {
        let now = now_ms();
        let zone = self.zone.clone();
        let zone = zone
            .as_ref()
            .map_or_else(TimeZoneRef::utc, TimeZone::as_ref);
        let due = self.as_mut().rust_mut().book.due(now, zone);
        let gone: Vec<&Alarm> = due
            .iter()
            .filter(|a| a.one_shot || a.repeat.is_empty())
            .collect();
        if gone.is_empty() {
            self.as_mut().schedule();
        } else {
            let shown = gone.iter().any(|a| !a.hidden);
            self.as_mut().changed(shown);
        }
        for alarm in due {
            self.as_mut().ring(alarm);
        }
    }

    fn ring(mut self: Pin<&mut Self>, alarm: Alarm) {
        log::warn("alarms", format_args!("ringing: {}", alarm.label));
        let (id, label) = (
            QString::from(alarm.id.as_str()),
            QString::from(alarm.label.as_str()),
        );
        let (sound, vibrate) = (!alarm.sound.is_empty(), alarm.vibrate);
        self.as_mut().rust_mut().active.push(alarm);
        self.as_mut().publish_active();
        self.as_mut().alarm_triggered(&id, &label);
        self.ringing(sound, vibrate);
    }

    fn fire(mut self: Pin<&mut Self>, zone: Option<TimeZone>) {
        if zone.is_some() {
            self.as_mut().rust_mut().zone = zone;
        }
        self.check_alarms();
    }
}

struct Alarm1 {
    qt: cxx_qt::CxxQtThread<Alarms>,
}

impl Alarm1 {
    async fn call<R: Send + 'static>(
        &self,
        h: &Header<'_>,
        f: impl FnOnce(Pin<&mut Alarms>) -> R + Send + 'static,
    ) -> fdo::Result<R> {
        ipc::admit(h, "Alarm", &["alarms", "system"]).await?;
        ipc::on_gui(&self.qt, f).await
    }
}

fn listed<'a>(alarms: impl Iterator<Item = &'a Alarm>) -> Vec<OwnedValue> {
    alarms.map(|a| value(a.to_state())).collect()
}

#[zbus::interface(name = "org.marathonos.Shell.Alarm1")]
impl Alarm1 {
    async fn get_alarms(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<OwnedValue>> {
        self.call(&h, |obj| {
            listed(obj.book.alarms.iter().filter(|a| !a.hidden))
        })
        .await
    }

    async fn get_active_alarms(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<OwnedValue>> {
        self.call(&h, |obj| listed(obj.active.iter())).await
    }

    async fn create_alarm(
        &self,
        time: String,
        label: String,
        repeat: Vec<i32>,
        options: State,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<String> {
        let options = Changes::from_dbus(&options);
        self.call(&h, move |obj| obj.create(time, label, repeat, &options))
            .await
    }

    async fn update_alarm(
        &self,
        id: String,
        updates: State,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<bool> {
        let updates = Changes::from_dbus(&updates);
        self.call(&h, move |obj| obj.update(&id, &updates)).await
    }

    async fn delete_alarm(&self, id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        self.call(&h, move |obj| obj.delete_alarm(&QString::from(&id)))
            .await
    }

    async fn enable_alarm(&self, id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        self.call(&h, move |obj| obj.enable_alarm(&QString::from(&id)))
            .await
    }

    async fn disable_alarm(&self, id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        self.call(&h, move |obj| obj.disable_alarm(&QString::from(&id)))
            .await
    }

    async fn snooze_alarm(&self, id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        self.call(&h, move |obj| obj.snooze_alarm(&QString::from(&id)))
            .await
    }

    async fn dismiss_alarm(&self, id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        self.call(&h, move |obj| obj.dismiss_alarm(&QString::from(&id)))
            .await
    }

    async fn stop_all(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        self.call(&h, Alarms::stop_all).await
    }

    async fn trigger_alarm_now(
        &self,
        label: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        self.call(&h, move |obj| obj.trigger_alarm_now(&QString::from(&label)))
            .await
    }
}

/// Waits the time it was last given, then has the shell check; the time
/// zone is read again for each check, off the GUI thread.
async fn timer(qt: cxx_qt::CxxQtThread<Alarms>, waits: Receiver<Option<Duration>>) {
    let zone = blocking::unblock(|| TimeZone::local().ok()).await;
    qt.queue(move |mut obj| {
        obj.as_mut().rust_mut().zone = zone;
        obj.schedule();
    })
    .ok();
    let mut wait = None;
    loop {
        match io::recv_within(&waits, wait).await {
            Some(Err(_)) => return,
            Some(Ok(w)) => wait = w,
            None => {
                wait = None;
                let zone = blocking::unblock(|| TimeZone::local().ok()).await;
                qt.queue(move |obj| obj.fire(zone)).ok();
            }
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use tz::{TimeZone, UtcDateTime};

    use super::{Alarm, Book};

    fn ms(y: i32, mo: u8, d: u8, h: u8, mi: u8) -> i64 {
        UtcDateTime::new(y, mo, d, h, mi, 0, 0).unwrap().unix_time() * 1000
    }

    fn alarm(time: &str, repeat: &[i32]) -> Alarm {
        Alarm {
            id: time.to_owned(),
            time: time.to_owned(),
            repeat: repeat.to_vec(),
            enabled: true,
            ..Alarm::default()
        }
    }

    #[test]
    fn an_alarm_rings_at_its_next_minute_on_its_days() {
        let utc = TimeZone::utc();
        // Tuesday 2026-10-20 08:00 UTC.
        let now = ms(2026, 10, 20, 8, 0);
        assert_eq!(
            alarm("09:30", &[]).next(now, utc.as_ref()),
            Some(ms(2026, 10, 20, 9, 30))
        );
        assert_eq!(
            alarm("07:00", &[]).next(now, utc.as_ref()),
            Some(ms(2026, 10, 21, 7, 0))
        );
        assert_eq!(
            alarm("07:00", &[0, 6]).next(now, utc.as_ref()),
            Some(ms(2026, 10, 24, 7, 0))
        );
        assert_eq!(
            alarm("08:00", &[2]).next(now, utc.as_ref()),
            Some(ms(2026, 10, 27, 8, 0))
        );
        assert_eq!(alarm("bad", &[]).next(now, utc.as_ref()), None);
        let eest = TimeZone::fixed(3 * 3600).unwrap();
        assert_eq!(
            alarm("09:30", &[]).next(now, eest.as_ref()),
            Some(ms(2026, 10, 21, 6, 30))
        );
    }

    #[test]
    fn a_one_off_turns_off_once_it_rings_and_a_timer_goes() {
        let utc = TimeZone::utc();
        let now = ms(2026, 10, 20, 6, 59);
        let mut book = Book {
            alarms: vec![alarm("07:00", &[]), alarm("07:00", &[0, 1, 2, 3, 4, 5, 6])],
            ..Book::default()
        };
        book.alarms.push(Alarm {
            id: "timer".into(),
            one_shot: true,
            hidden: true,
            at: now + 60_000,
            enabled: true,
            ..Alarm::default()
        });
        assert_eq!(book.schedule(now, utc.as_ref()), Some(now + 60_000));
        // The timer fires a little early.
        let due = book.due(now + 59_990, utc.as_ref());
        assert_eq!(due.len(), 3);
        assert_eq!(book.alarms.len(), 2);
        assert_eq!(
            book.alarms.iter().map(|a| a.enabled).collect::<Vec<_>>(),
            [false, true]
        );
        // and the daily alarm doesn't ring again that minute.
        assert_eq!(
            book.schedule(now + 59_990, utc.as_ref()),
            Some(ms(2026, 10, 21, 7, 0))
        );
        assert_eq!(book.due(now + 60_010, utc.as_ref()), []);
    }

    #[test]
    fn alarms_keep_their_json() {
        let json = r#"[{"id":"a","time":"07:15","enabled":true,"label":"Work","repeat":[1,2],"sound":"default","vibrate":true,"snoozeEnabled":true,"snoozeDuration":5}]"#;
        let alarms: Vec<Alarm> = serde_json::from_str(json).unwrap();
        assert_eq!(alarms[0].repeat, [1, 2]);
        assert_eq!(serde_json::to_string(&alarms).unwrap(), json);
        let old: Vec<Alarm> = serde_json::from_str(r#"[{"id":"b","time":"06:00"}]"#).unwrap();
        assert_eq!(old[0].snooze_duration, 10);
    }
}
