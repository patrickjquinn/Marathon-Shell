//! `Calendar`: the Calendar app's events, kept in the `calendar/events`
//! setting, with a notification at each event's reminder.

use std::collections::{HashMap, VecDeque};
use std::pin::Pin;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use jiff::civil::Date;
use jiff::{Span, Zoned};
use zbus::{OwnedVariant as OwnedValue, Variant as Value};

use crate::shell::{allowed, Service};
use crate::{notifications, variant};
use marathon_rt::io;
use marathon_rt::log;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, events, READ, NOTIFY = events_changed)]
        type Calendar = super::CalendarRust;

        #[qsignal]
        #[cxx_name = "eventsChanged"]
        fn events_changed(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "createEvent"]
        fn create_event(
            self: Pin<&mut Calendar>,
            event: &QMap_QString_QVariant,
        ) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "updateEvent"]
        fn update_event(self: Pin<&mut Calendar>, event: &QMap_QString_QVariant) -> bool;
        #[qinvokable]
        #[cxx_name = "deleteEvent"]
        fn delete_event(self: Pin<&mut Calendar>, id: i32) -> bool;
    }

    impl cxx_qt::Threading for Calendar {}
    impl cxx_qt::Initialize for Calendar {}
}

use qobject::Calendar;

const SETTINGS: Service = Service::shell("Settings");
const KEY: &str = "calendar/events";

type Event = HashMap<String, Value<'static>>;

#[derive(Default)]
pub struct CalendarRust {
    events: QList<QVariant>,
    list: Vec<Event>,
    // Reminders already shown, so a minute's two checks show one.
    shown: VecDeque<String>,
}

fn text<'a>(event: &'a Event, key: &str) -> &'a str {
    match event.get(key) {
        Some(Value::Str(s)) => s.as_str(),
        _ => "",
    }
}

fn int(event: &Event, key: &str) -> i64 {
    match event.get(key) {
        // QML hands whole numbers over as doubles.
        #[allow(clippy::cast_possible_truncation, reason = "whole numbers from QML")]
        Some(Value::F64(f)) => *f as i64,
        Some(v) => variant::number(v).unwrap_or(0),
        None => 0,
    }
}

fn as_qt(event: &Event) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    for (key, value) in event {
        map.insert(QString::from(key), variant::to_qt(value));
    }
    map
}

fn normalized(event: &QMap<QMapPair_QString_QVariant>) -> Event {
    let mut event = variant::map(event);
    for (key, default) in [
        ("title", Value::from("")),
        ("date", Value::from("")),
        ("time", Value::from("")),
        ("allDay", Value::from(false)),
        ("recurring", Value::from("none")),
        ("description", Value::from("")),
        ("reminder", Value::from(0i32)),
    ] {
        event.entry(key.to_owned()).or_insert(default);
    }
    event
}

/// The event happens on `day`, itself or as a repeat.
fn falls_on(event: &Event, day: Date) -> bool {
    let Ok(first) = text(event, "date").parse::<Date>() else {
        return false;
    };
    if first == day {
        return true;
    }
    if day < first {
        return false;
    }
    match text(event, "recurring") {
        "daily" => true,
        "weekly" => first.until(day).is_ok_and(|span| span.get_days() % 7 == 0),
        "monthly" => first.day() == day.day(),
        _ => false,
    }
}

/// Its reminder (minutes before; negative for none) is due at `now`.
fn due(event: &Event, now: &Zoned) -> bool {
    let reminder = int(event, "reminder");
    if reminder < 0 {
        return false;
    }
    let Ok(at) = now.checked_add(Span::new().minutes(reminder)) else {
        return false;
    };
    text(event, "time") == at.strftime("%H:%M").to_string() && falls_on(event, at.date())
}

impl CalendarRust {
    fn publish(mut obj: Pin<&mut Calendar>) {
        let events = obj.list.iter().map(|e| QVariant::from(&as_qt(e))).collect();
        obj.as_mut().rust_mut().events = events;
        obj.as_mut().events_changed();
        let stored: Vec<Value<'static>> = obj
            .list
            .iter()
            .map(|e| {
                Value::from(
                    e.iter()
                        .filter_map(|(k, v)| Some((k.clone(), v.try_clone().ok()?)))
                        .collect::<HashMap<_, _>>(),
                )
            })
            .collect();
        SETTINGS.call("Set", (KEY.to_owned(), Value::from(stored)));
    }

    fn remind(mut obj: Pin<&mut Calendar>) {
        let now = Zoned::now();
        let minute = now.strftime("%Y-%m-%d %H:%M").to_string();
        let due: Vec<(String, String, String)> = obj
            .list
            .iter()
            .filter(|e| due(e, &now))
            .map(|e| {
                (
                    format!("{}_{minute}", int(e, "id")),
                    text(e, "title").to_owned(),
                    text(e, "time").to_owned(),
                )
            })
            .collect();
        for (key, title, time) in due {
            let shown = &mut obj.as_mut().rust_mut().shown;
            if shown.contains(&key) {
                continue;
            }
            shown.push_back(key);
            if shown.len() > 50 {
                shown.pop_front();
            }
            io::spawn(async move {
                let hints = HashMap::from([
                    ("category", Value::from("reminder")),
                    ("urgency", Value::U8(2)),
                ]);
                let body = (
                    "calendar",
                    0u32,
                    "qrc:/images/calendar.svg",
                    title,
                    time,
                    vec!["Dismiss", "Dismiss"],
                    hints,
                    5000i32,
                );
                let sent = async {
                    if allowed("notifications", &mut false).await? {
                        notifications::call("Notify", &body).await.map(drop)
                    } else {
                        Ok(())
                    }
                };
                if let Err(e) = sent.await {
                    log::warn("Calendar", format_args!("reminder: {e}"));
                }
            });
        }
    }
}

impl cxx_qt::Initialize for Calendar {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let stored: Option<OwnedValue> = SETTINGS
                .ask("Get", &(KEY, Value::from(Vec::<Value>::new())))
                .await
                .ok();
            let list: Vec<Event> = match stored.as_deref().map(variant::to_qt) {
                Some(v) => v
                    .value::<QList<QVariant>>()
                    .map(|l| {
                        l.iter()
                            .filter_map(|e| {
                                e.value::<QMap<QMapPair_QString_QVariant>>()
                                    .map(|m| variant::map(&m))
                            })
                            .collect()
                    })
                    .unwrap_or_default(),
                None => Vec::new(),
            };
            qt.queue(move |mut obj| {
                obj.as_mut().rust_mut().list = list;
                let events = obj.list.iter().map(|e| QVariant::from(&as_qt(e))).collect();
                obj.as_mut().rust_mut().events = events;
                obj.as_mut().events_changed();
                CalendarRust::remind(obj);
            })
            .ok();
            loop {
                async_io::Timer::after(Duration::from_secs(60)).await;
                qt.queue(CalendarRust::remind).ok();
            }
        });
    }
}

impl Calendar {
    fn create_event(
        mut self: Pin<&mut Self>,
        event: &QMap<QMapPair_QString_QVariant>,
    ) -> QMap<QMapPair_QString_QVariant> {
        let mut event = normalized(event);
        let id = self.list.iter().map(|e| int(e, "id")).max().unwrap_or(0) + 1;
        event.insert(
            "id".to_owned(),
            Value::from(i32::try_from(id).unwrap_or(i32::MAX)),
        );
        event.insert(
            "timestamp".to_owned(),
            Value::from(jiff::Timestamp::now().as_millisecond()),
        );
        let created = as_qt(&event);
        self.as_mut().rust_mut().list.push(event);
        CalendarRust::publish(self);
        created
    }

    fn update_event(mut self: Pin<&mut Self>, event: &QMap<QMapPair_QString_QVariant>) -> bool {
        let mut event = normalized(event);
        let id = int(&event, "id");
        let Some(at) = self.list.iter().position(|e| int(e, "id") == id) else {
            return false;
        };
        event.insert("id".to_owned(), Value::from(i32::try_from(id).unwrap_or(0)));
        self.as_mut().rust_mut().list[at] = event;
        CalendarRust::publish(self);
        true
    }

    fn delete_event(mut self: Pin<&mut Self>, id: i32) -> bool {
        let Some(at) = self.list.iter().position(|e| int(e, "id") == i64::from(id)) else {
            return false;
        };
        self.as_mut().rust_mut().list.remove(at);
        CalendarRust::publish(self);
        true
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn event(date: &str, time: &str, recurring: &str, reminder: i32) -> Event {
        HashMap::from([
            ("date".to_owned(), Value::from(date.to_owned())),
            ("time".to_owned(), Value::from(time.to_owned())),
            ("recurring".to_owned(), Value::from(recurring.to_owned())),
            ("reminder".to_owned(), Value::from(reminder)),
        ])
    }

    fn day(s: &str) -> Date {
        s.parse().unwrap()
    }

    #[test]
    fn repeats_fall_on_their_days() {
        assert!(falls_on(
            &event("2026-10-20", "", "none", 0),
            day("2026-10-20")
        ));
        assert!(!falls_on(
            &event("2026-10-20", "", "none", 0),
            day("2026-10-21")
        ));
        assert!(falls_on(
            &event("2026-10-20", "", "daily", 0),
            day("2026-11-03")
        ));
        assert!(falls_on(
            &event("2026-10-20", "", "weekly", 0),
            day("2026-10-27")
        ));
        assert!(!falls_on(
            &event("2026-10-20", "", "weekly", 0),
            day("2026-10-28")
        ));
        assert!(falls_on(
            &event("2026-10-20", "", "monthly", 0),
            day("2026-12-20")
        ));
        assert!(!falls_on(
            &event("2026-10-20", "", "daily", 0),
            day("2026-10-19")
        ));
    }

    #[test]
    fn reminders_come_ahead_of_the_event() {
        let now: Zoned = "2026-10-20T09:45[UTC]".parse().unwrap();
        assert!(due(&event("2026-10-20", "10:00", "none", 15), &now));
        assert!(!due(&event("2026-10-20", "10:00", "none", 0), &now));
        assert!(due(&event("2026-10-13", "09:45", "weekly", 0), &now));
        assert!(!due(&event("2026-10-20", "09:45", "none", -1), &now));
    }
}
