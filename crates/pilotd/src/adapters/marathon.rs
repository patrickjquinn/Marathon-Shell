// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Marathon OS: the shell's services on the session bus
//! (`org.marathonos.Shell`, shell/src/ipc/shellservices.h in Marathon).
//! Used instead of timed, mkcal, qtcontacts-sqlite, oFono and ConnMan when
//! the shell owns its name. The shell checks pilotd's permissions by its
//! systemd unit (Marathon's /usr/share/marathon-shell/services).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use serde_json::Value as Json;
use zbus::zvariant::{OwnedValue, Value};

use super::{
    AdapterError, Calendar, CalendarEvent, Clock, ClockItem, Contact, Contacts, DeviceToggles,
    Telephony, Toggle,
};
use crate::localtime::{self, LocalNow};

pub const SHELL: &str = "org.marathonos.Shell";
const ROOT: &str = "/org/marathonos/Shell";

/// Whether the Marathon shell is on this session bus.
pub fn present(session: &zbus::Connection) -> bool {
    zbus::block_on(async {
        let dbus = zbus::fdo::DBusProxy::new(session).await.ok()?;
        dbus.name_has_owner(SHELL.try_into().ok()?).await.ok()
    })
    .unwrap_or(false)
}

/// The daemon that serves `object` in place of the shell, else the shell.
fn bus_for(object: &str) -> &'static str {
    match object {
        "Sms" | "CallHistory" => "org.marathonos.Telephony",
        "Contacts" => "org.marathonos.Dav",
        _ => SHELL,
    }
}

async fn call<B, R>(
    session: &zbus::Connection,
    object: &str,
    method: &str,
    body: &B,
) -> Result<R, AdapterError>
where
    B: serde::Serialize + zbus::zvariant::DynamicType,
    R: for<'d> zbus::zvariant::DynamicDeserialize<'d>,
{
    let reply = session
        .call_method(
            Some(bus_for(object)),
            format!("{ROOT}/{object}").as_str(),
            Some(format!("{SHELL}.{object}1").as_str()),
            method,
            body,
        )
        .await?;
    Ok(reply.body().deserialize()?)
}

/// A D-Bus value as JSON: Qt's `QVariantList` and `QVariantMap` arrive as
/// `av` and `a{sv}`.
pub fn json(v: &Value<'_>) -> Json {
    match v {
        Value::U8(n) => Json::from(*n),
        Value::Bool(b) => Json::from(*b),
        Value::I16(n) => Json::from(*n),
        Value::U16(n) => Json::from(*n),
        Value::I32(n) => Json::from(*n),
        Value::U32(n) => Json::from(*n),
        Value::I64(n) => Json::from(*n),
        Value::U64(n) => Json::from(*n),
        Value::F64(n) => Json::from(*n),
        Value::Str(s) => Json::from(s.as_str()),
        Value::ObjectPath(p) => Json::from(p.as_str()),
        Value::Value(inner) => json(inner),
        Value::Array(a) => Json::Array(a.iter().map(json).collect()),
        Value::Dict(d) => Json::Object(
            d.iter()
                .map(|(k, v)| {
                    let key = match json(k) {
                        Json::String(s) => s,
                        other => other.to_string(),
                    };
                    (key, json(v))
                })
                .collect(),
        ),
        Value::Structure(s) => Json::Array(s.fields().iter().map(json).collect()),
        _ => Json::Null,
    }
}

fn str_field<'a>(o: &'a Json, k: &str) -> &'a str {
    o.get(k).and_then(Json::as_str).unwrap_or("")
}

fn hhmm(s: &str) -> Option<(u32, u32)> {
    let (h, m) = s.split_once(':')?;
    let (h, m) = (h.trim().parse().ok()?, m.trim().parse().ok()?);
    (h < 24 && m < 60).then_some((h, m))
}

/// A stable cookie for a shell alarm id.
pub fn cookie(id: &str) -> u32 {
    id.bytes()
        .fold(0x811c_9dc5_u32, |h, b| {
            (h ^ u32::from(b)).wrapping_mul(0x0100_0193)
        })
        .max(1)
}

/// Clock's alarms (AlarmManagerCpp): an alarm at a time of day, and
/// one-shot alarms at an instant for timers and reminders.
pub struct ShellClock {
    pub session: zbus::Connection,
    /// What Pilot set, by shell id: kind and a timer's length.
    pub made: Mutex<HashMap<String, (&'static str, Option<u32>)>>,
}

impl ShellClock {
    pub fn new(session: zbus::Connection) -> ShellClock {
        ShellClock {
            session,
            made: Mutex::new(HashMap::new()),
        }
    }

    async fn create(
        &self,
        time: &str,
        label: &str,
        at_ms: Option<i64>,
        kind: &'static str,
        seconds: Option<u32>,
    ) -> Result<u32, AdapterError> {
        let mut options: HashMap<&str, Value<'_>> = HashMap::new();
        if let Some(at) = at_ms {
            options.insert("oneShot", Value::from(true));
            options.insert("at", Value::from(at));
        }
        let id: String = call(
            &self.session,
            "Alarm",
            "CreateAlarm",
            &(time, label, Vec::<i32>::new(), options),
        )
        .await?;
        if id.is_empty() {
            return Err(AdapterError::Failed("the clock refused the alarm".into()));
        }
        let c = cookie(&id);
        self.made
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(id, (kind, seconds));
        Ok(c)
    }

    async fn alarms(&self) -> Result<Vec<Json>, AdapterError> {
        let list: Vec<OwnedValue> = call(&self.session, "Alarm", "GetAlarms", &()).await?;
        Ok(list.iter().map(|v| json(v)).collect())
    }
}

/// The shell's alarms as [`ClockItem`]s, soonest first.
pub fn clock_items<S: std::hash::BuildHasher>(
    alarms: &[Json],
    made: &HashMap<String, (&'static str, Option<u32>), S>,
    now: &LocalNow,
) -> Vec<ClockItem> {
    let mut items: Vec<ClockItem> = alarms
        .iter()
        .filter(|a| a.get("enabled").and_then(Json::as_bool).unwrap_or(false))
        .filter_map(|a| {
            let id = str_field(a, "id");
            let one_shot = a.get("oneShot").and_then(Json::as_bool).unwrap_or(false);
            let time = str_field(a, "time");
            let at = if one_shot {
                a.get("at").and_then(Json::as_i64)? / 1000
            } else {
                let (h, m) = hhmm(time)?;
                let days: Vec<u32> = a
                    .get("repeat")
                    .and_then(Json::as_array)
                    .map(|r| {
                        r.iter()
                            .filter_map(Json::as_u64)
                            .filter_map(|d| u32::try_from(d).ok())
                            .collect()
                    })
                    .unwrap_or_default();
                (0..8)
                    .map(|d| (d, now.local_time(d, h, m)))
                    .find(|(d, t)| {
                        *t > now.epoch
                            && (days.is_empty()
                                || days.contains(
                                    &((now.weekday + u32::try_from(*d).unwrap_or(0)) % 7),
                                ))
                    })?
                    .1
            };
            let (kind, seconds) = made.get(id).copied().unwrap_or(if one_shot {
                ("reminder", None)
            } else {
                ("alarm", None)
            });
            Some(ClockItem {
                cookie: cookie(id),
                kind: kind.into(),
                title: str_field(a, "label").to_owned(),
                at,
                seconds,
                time: (kind == "alarm").then(|| time.to_owned()),
            })
        })
        .collect();
    items.sort_by_key(|i| i.at);
    items
}

#[async_trait]
impl Clock for ShellClock {
    async fn set_timer(&self, seconds: u32, label: Option<&str>) -> Result<u32, AdapterError> {
        let at = (localtime::now().epoch + i64::from(seconds)) * 1000;
        self.create(
            "",
            label.unwrap_or("Timer"),
            Some(at),
            "timer",
            Some(seconds),
        )
        .await
    }

    async fn set_alarm(
        &self,
        hour: u32,
        minute: u32,
        label: Option<&str>,
    ) -> Result<u32, AdapterError> {
        let time = format!("{hour:02}:{minute:02}");
        self.create(&time, label.unwrap_or(""), None, "alarm", None)
            .await
    }

    async fn create_reminder(&self, title: &str, at: i64) -> Result<u32, AdapterError> {
        self.create("", title, Some(at * 1000), "reminder", None)
            .await
    }

    async fn upcoming(&self) -> Result<Vec<ClockItem>, AdapterError> {
        let alarms = self.alarms().await?;
        let made = self
            .made
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        Ok(clock_items(&alarms, &made, &localtime::now()))
    }

    async fn cancel(&self, c: u32) -> Result<bool, AdapterError> {
        let alarms = self.alarms().await?;
        let Some(id) = alarms
            .iter()
            .map(|a| str_field(a, "id"))
            .find(|id| cookie(id) == c)
            .map(str::to_owned)
        else {
            return Ok(false);
        };
        let done: bool = call(&self.session, "Alarm", "DeleteAlarm", &(id.as_str(),)).await?;
        Ok(done)
    }
}

/// The Calendar app's events: `calendar/events` in the shell's settings
/// (`CalendarManagerCpp`), a list of {title, date "yyyy-MM-dd", time and
/// endTime "HH:mm", allDay, recurring none/daily/weekly/monthly, location}.
pub struct ShellCalendar {
    pub session: zbus::Connection,
}

/// Occurrences of the shell's events overlapping `[from, to)`, earliest
/// first, at most `limit`.
pub fn calendar_events(
    events: &[Json],
    from: i64,
    to: i64,
    limit: usize,
    at: fn(i64) -> LocalNow,
) -> Vec<CalendarEvent> {
    let start = at(from);
    let days = ((to - from) / 86_400 + 2).clamp(1, 400);
    let mut out = Vec::new();
    for e in events {
        let date: Vec<u32> = str_field(e, "date")
            .split('-')
            .filter_map(|p| p.parse().ok())
            .collect();
        let [year, month, day] = date[..] else {
            continue;
        };
        let all_day = e.get("allDay").and_then(Json::as_bool).unwrap_or(false);
        let (hour, minute) = if all_day {
            (0, 0)
        } else {
            hhmm(str_field(e, "time")).unwrap_or((12, 0))
        };
        let length = if all_day {
            86_400
        } else {
            match hhmm(str_field(e, "endTime")) {
                Some((eh, em)) => {
                    let mins =
                        (i64::from(eh * 60 + em) - i64::from(hour * 60 + minute)).rem_euclid(1440);
                    if mins == 0 {
                        3600
                    } else {
                        mins * 60
                    }
                }
                None => 3600,
            }
        };
        let recurring = str_field(e, "recurring");
        // The event's first day, as a day count from `start`'s day.
        let first = (day_start(i32::try_from(year).unwrap_or(1970), month, day, &start)
            - start.midnight())
        .div_euclid(86_400);
        for n in -1..days {
            if n < first {
                continue;
            }
            let occurs = match recurring {
                "daily" => true,
                "weekly" => (n - first) % 7 == 0,
                "monthly" => at(start.local_time(n, 12, 0)).day == day,
                _ => n == first,
            };
            if !occurs {
                continue;
            }
            let begins = start.local_time(n, hour, minute);
            let end = begins + length;
            if begins < to && end > from {
                out.push(CalendarEvent {
                    title: str_field(e, "title").to_owned(),
                    start: begins,
                    end,
                    all_day,
                    location: Some(str_field(e, "location").to_owned()).filter(|l| !l.is_empty()),
                });
            }
        }
    }
    out.sort_by_key(|e| e.start);
    out.truncate(limit);
    out
}

/// Local midnight starting `y-m-d`, by `reference`'s zone.
fn day_start(y: i32, m: u32, d: u32, reference: &LocalNow) -> i64 {
    // Days since 0000-03-01 (Howard Hinnant's days_from_civil).
    let civil = |y: i32, m: u32, d: u32| -> i64 {
        let (y, m) = if m <= 2 {
            (i64::from(y) - 1, i64::from(m) + 9)
        } else {
            (i64::from(y), i64::from(m) - 3)
        };
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let doy = (153 * m + 2) / 5 + i64::from(d) - 1;
        era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy
    };
    let delta = civil(y, m, d) - civil(reference.year, reference.month, reference.day);
    reference.local_time(delta, 0, 0)
}

impl Calendar for ShellCalendar {
    fn events(&self, from: i64, to: i64, limit: usize) -> Result<Vec<CalendarEvent>, AdapterError> {
        let raw: OwnedValue = zbus::block_on(call(
            &self.session,
            "Settings",
            "Get",
            &("calendar/events", Value::from("")),
        ))?;
        let list = match json(&raw) {
            Json::Array(a) => a,
            Json::String(s) if !s.is_empty() => serde_json::from_str(&s).unwrap_or_default(),
            _ => Vec::new(),
        };
        Ok(calendar_events(&list, from, to, limit, localtime::at))
    }
}

/// The address book (`ContactsManager`), names cached for a minute as the
/// redactor asks for them on every turn.
pub struct ShellContacts {
    pub session: zbus::Connection,
    names: Mutex<Option<(Instant, Vec<String>)>>,
}

impl ShellContacts {
    pub fn new(session: zbus::Connection) -> ShellContacts {
        ShellContacts {
            session,
            names: Mutex::new(None),
        }
    }

    fn list(&self, method: &str, query: Option<&str>) -> Result<Vec<Json>, AdapterError> {
        let list: Vec<OwnedValue> = match query {
            Some(q) => zbus::block_on(call(&self.session, "Contacts", method, &(q,)))?,
            None => zbus::block_on(call(&self.session, "Contacts", method, &()))?,
        };
        Ok(list.iter().map(|v| json(v)).collect())
    }
}

pub fn contact(c: &Json) -> Contact {
    let one = |k: &str| {
        Some(str_field(c, k).to_owned())
            .filter(|s| !s.is_empty())
            .into_iter()
            .collect()
    };
    Contact {
        name: str_field(c, "name").to_owned(),
        phones: one("phone"),
        emails: one("email"),
    }
}

impl Contacts for ShellContacts {
    fn names(&self) -> Vec<String> {
        let mut cache = self
            .names
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some((when, names)) = cache.as_ref() {
            if when.elapsed() < Duration::from_secs(60) {
                return names.clone();
            }
        }
        let names: Vec<String> = match self.list("GetContacts", None) {
            Ok(l) => l
                .iter()
                .map(|c| str_field(c, "name").to_owned())
                .filter(|n| !n.is_empty())
                .collect(),
            Err(e) => {
                log::warn!("contacts: {e}");
                Vec::new()
            }
        };
        *cache = Some((Instant::now(), names.clone()));
        names
    }

    fn lookup(&self, query: &str, limit: usize) -> Result<Vec<Contact>, AdapterError> {
        Ok(self
            .list("SearchContacts", Some(query))?
            .iter()
            .map(contact)
            .take(limit)
            .collect())
    }
}

/// Calls and texts through the shell (`TelephonyService` over `ModemManager`,
/// `SMSService`), so they show in Phone and Messages.
pub struct ShellTelephony {
    pub session: zbus::Connection,
}

#[async_trait]
impl Telephony for ShellTelephony {
    async fn dial(&self, number: &str) -> Result<(), AdapterError> {
        let n = super::telephony::dialable(number)
            .ok_or_else(|| AdapterError::Failed(format!("{number:?} is not a phone number")))?;
        call::<_, ()>(&self.session, "Telephony", "Dial", &(n.as_str(),)).await
    }

    async fn send_sms(&self, to: &str, text: &str) -> Result<(), AdapterError> {
        let n = super::telephony::dialable(to)
            .ok_or_else(|| AdapterError::Failed(format!("{to:?} is not a phone number")))?;
        call::<_, ()>(&self.session, "Sms", "SendMessage", &(n.as_str(), text)).await
    }
}

/// Wi-Fi and flight mode (`Network1`, `NetworkManager`), mobile data (`Modem1`,
/// `ModemManager`), Bluetooth (`Bluetooth1`, `BlueZ` and rfkill).
pub struct ShellToggles {
    pub session: zbus::Connection,
}

/// Object, `GetState` key, and the method that sets it (`None`: one
/// method each way).
pub fn toggle_target(
    what: Toggle,
) -> (
    &'static str,
    &'static str,
    Option<&'static str>,
    [&'static str; 2],
) {
    match what {
        Toggle::Wifi => (
            "Network",
            "wifiEnabled",
            None,
            ["EnableWifi", "DisableWifi"],
        ),
        Toggle::FlightMode => (
            "Network",
            "airplaneModeEnabled",
            Some("SetAirplaneMode"),
            ["", ""],
        ),
        Toggle::MobileData => ("Modem", "dataEnabled", None, ["EnableData", "DisableData"]),
        Toggle::Bluetooth => ("Bluetooth", "enabled", Some("SetEnabled"), ["", ""]),
    }
}

#[async_trait]
impl DeviceToggles for ShellToggles {
    async fn set(&self, what: Toggle, on: bool) -> Result<(), AdapterError> {
        let (object, _, setter, [enable, disable]) = toggle_target(what);
        match setter {
            Some(m) => call::<_, ()>(&self.session, object, m, &(on,)).await,
            None => {
                call::<_, ()>(
                    &self.session,
                    object,
                    if on { enable } else { disable },
                    &(),
                )
                .await
            }
        }
    }

    async fn get(&self, what: Toggle) -> Result<bool, AdapterError> {
        let (object, key, _, _) = toggle_target(what);
        let state: HashMap<String, OwnedValue> =
            call(&self.session, object, "GetState", &()).await?;
        state
            .get(key)
            .and_then(|v| bool::try_from(v).ok())
            .ok_or_else(|| AdapterError::Failed(format!("{key} not reported")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json as j;

    #[test]
    fn values_become_json() {
        let mut d: HashMap<&str, Value<'_>> = HashMap::new();
        d.insert("name", Value::from("Anna"));
        d.insert("id", Value::from(3i32));
        let v = Value::from(vec![Value::Value(Box::new(Value::from(d)))]);
        assert_eq!(json(&v), j!([{"name": "Anna", "id": 3}]));
    }

    #[test]
    fn cookies_are_stable_and_non_zero() {
        assert_eq!(cookie("alarm_1"), cookie("alarm_1"));
        assert_ne!(cookie("alarm_1"), cookie("alarm_2"));
        assert_ne!(cookie(""), 0);
    }

    #[test]
    fn alarms_timers_and_reminders() {
        let now = LocalNow::fixed_utc(1_790_966_550); // Fri 18:42:30 UTC
        let mid = now.midnight();
        let alarms = vec![
            j!({"id": "a", "time": "07:15", "label": "Alarm", "enabled": true, "repeat": []}),
            j!({"id": "off", "time": "06:00", "label": "Off", "enabled": false, "repeat": []}),
            j!({"id": "mon", "time": "08:00", "label": "Work", "enabled": true, "repeat": [1]}),
            j!({"id": "t", "time": "18:52", "label": "Timer", "enabled": true, "oneShot": true,
                "at": (now.epoch + 600) * 1000, "repeat": []}),
            j!({"id": "r", "time": "20:00", "label": "Call mum", "enabled": true, "oneShot": true,
                "at": (mid + 20 * 3600) * 1000, "repeat": []}),
        ];
        let made = HashMap::from([("t".to_owned(), ("timer", Some(600)))]);
        let items = clock_items(&alarms, &made, &now);
        let got: Vec<(&str, &str, i64)> = items
            .iter()
            .map(|i| (i.kind.as_str(), i.title.as_str(), i.at))
            .collect();
        assert_eq!(
            got,
            [
                ("timer", "Timer", now.epoch + 600),
                ("reminder", "Call mum", mid + 20 * 3600),
                ("alarm", "Alarm", mid + 86_400 + 7 * 3600 + 15 * 60),
                ("alarm", "Work", mid + 3 * 86_400 + 8 * 3600),
            ]
        );
        assert_eq!(items[0].seconds, Some(600));
        assert_eq!(items[2].time.as_deref(), Some("07:15"));
        assert_eq!(items[0].cookie, cookie("t"));
    }

    #[test]
    fn calendar_occurrences() {
        let now = LocalNow::fixed_utc(1_790_966_550); // Fri 2026-10-02 18:42:30 UTC
        let mid = now.midnight();
        let at = LocalNow::fixed_utc;
        let events = vec![
            j!({"title": "Dentist", "date": "2026-10-05", "time": "09:30", "endTime": "10:00",
                "allDay": false, "recurring": "none", "location": "Main St"}),
            j!({"title": "Standup", "date": "2026-09-01", "time": "10:00", "allDay": false,
                "recurring": "weekly"}),
            j!({"title": "Holiday", "date": "2026-10-03", "allDay": true, "recurring": "none"}),
            j!({"title": "Rent", "date": "2026-08-04", "time": "08:00", "recurring": "monthly"}),
            j!({"title": "Past", "date": "2026-10-01", "time": "08:00", "recurring": "none"}),
        ];
        let week = calendar_events(&events, now.epoch, mid + 8 * 86_400, 10, at);
        let got: Vec<(&str, i64, i64)> = week
            .iter()
            .map(|e| (e.title.as_str(), e.start - mid, e.end - e.start))
            .collect();
        // 2026-09-01 is a Tuesday: Standup on Tuesday 6 October; Rent on
        // the 4th of each month.
        assert_eq!(
            got,
            [
                ("Holiday", 86_400, 86_400),
                ("Rent", 2 * 86_400 + 8 * 3600, 3600),
                ("Dentist", 3 * 86_400 + 9 * 3600 + 1800, 1800),
                ("Standup", 4 * 86_400 + 10 * 3600, 3600),
            ]
        );
        assert_eq!(week[2].location.as_deref(), Some("Main St"));
        assert_eq!(
            calendar_events(&events, now.epoch, mid + 8 * 86_400, 2, at).len(),
            2
        );
    }
}
