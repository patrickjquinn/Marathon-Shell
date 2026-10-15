// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The Marathon adapters against a stand-in Marathon shell on a private
//! session bus (the method shapes of Marathon's shell/src/ipc/shellservices.h).

// zbus interfaces take their arguments by value.
#![allow(clippy::needless_pass_by_value, clippy::unused_self)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use pilotd::adapters::marathon::{
    self, ShellCalendar, ShellClock, ShellContacts, ShellTelephony, ShellToggles,
};
use pilotd::adapters::{
    Calendar as _, Clock as _, Contacts as _, DeviceToggles as _, Telephony as _, Toggle,
};
use shoal_push_client::testbus::TestBus;
use zbus::zvariant::{OwnedValue, Value};

type Calls = Arc<Mutex<Vec<String>>>;

fn map(pairs: &[(&str, Value<'_>)]) -> OwnedValue {
    let m: HashMap<String, Value<'_>> = pairs
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.try_clone().unwrap()))
        .collect();
    Value::from(m).try_into().unwrap()
}

struct Alarm(Calls, Mutex<Vec<(String, String, i64)>>);

#[zbus::interface(name = "org.marathonos.Shell.Alarm1")]
impl Alarm {
    #[zbus(name = "GetAlarms")]
    fn get_alarms(&self) -> Vec<OwnedValue> {
        self.1
            .lock()
            .unwrap()
            .iter()
            .map(|(id, label, at)| {
                map(&[
                    ("id", Value::from(id.as_str())),
                    ("label", Value::from(label.as_str())),
                    ("enabled", Value::from(true)),
                    ("oneShot", Value::from(true)),
                    ("at", Value::from(*at)),
                    ("time", Value::from("")),
                    ("repeat", Value::from(Vec::<i32>::new())),
                ])
            })
            .collect()
    }
    #[zbus(name = "CreateAlarm")]
    fn create_alarm(
        &self,
        time: String,
        label: String,
        repeat: Vec<i32>,
        options: HashMap<String, OwnedValue>,
    ) -> String {
        let one_shot = options
            .get("oneShot")
            .is_some_and(|v| bool::try_from(v).unwrap_or(false));
        let at = options
            .get("at")
            .and_then(|v| i64::try_from(v).ok())
            .unwrap_or(0);
        self.0
            .lock()
            .unwrap()
            .push(format!("create {time:?} {label} {repeat:?} {one_shot}"));
        let id = format!("alarm_{}", self.1.lock().unwrap().len());
        if one_shot {
            self.1.lock().unwrap().push((id.clone(), label, at));
        }
        id
    }
    #[zbus(name = "DeleteAlarm")]
    fn delete_alarm(&self, id: String) -> bool {
        let mut a = self.1.lock().unwrap();
        let before = a.len();
        a.retain(|(i, _, _)| *i != id);
        a.len() != before
    }
}

struct Settings;

#[zbus::interface(name = "org.marathonos.Shell.Settings1")]
impl Settings {
    #[zbus(name = "Get")]
    fn get(&self, key: String, default: OwnedValue) -> OwnedValue {
        assert_eq!(default, OwnedValue::from(zbus::zvariant::Str::from("")));
        assert_eq!(key, "calendar/events");
        let events = vec![map(&[
            ("title", Value::from("Dentist")),
            ("date", Value::from("2026-10-05")),
            ("time", Value::from("09:30")),
            ("endTime", Value::from("10:00")),
            ("allDay", Value::from(false)),
            ("recurring", Value::from("none")),
        ])];
        Value::from(events).try_into().unwrap()
    }
}

struct Contacts;

#[zbus::interface(name = "org.marathonos.Shell.Contacts1")]
impl Contacts {
    #[zbus(name = "GetContacts")]
    fn get_contacts(&self) -> Vec<OwnedValue> {
        vec![map(&[
            ("id", Value::from(1i32)),
            ("name", Value::from("Anna Virtanen")),
            ("phone", Value::from("+358401234567")),
            ("email", Value::from("")),
        ])]
    }
    #[zbus(name = "SearchContacts")]
    fn search_contacts(&self, q: String) -> Vec<OwnedValue> {
        if "anna virtanen".contains(&q.to_lowercase()) {
            self.get_contacts()
        } else {
            Vec::new()
        }
    }
}

struct Telephony(Calls);

#[zbus::interface(name = "org.marathonos.Shell.Telephony1")]
impl Telephony {
    #[zbus(name = "Dial")]
    fn dial(&self, number: String) {
        self.0.lock().unwrap().push(format!("dial {number}"));
    }
}

struct Network(Calls);

#[zbus::interface(name = "org.marathonos.Shell.Network1")]
impl Network {
    #[zbus(name = "GetState")]
    fn get_state(&self) -> HashMap<String, OwnedValue> {
        HashMap::from([
            ("wifiEnabled".to_owned(), OwnedValue::from(true)),
            ("airplaneModeEnabled".to_owned(), OwnedValue::from(false)),
        ])
    }
    #[zbus(name = "DisableWifi")]
    fn disable_wifi(&self) {
        self.0.lock().unwrap().push("wifi off".into());
    }
    #[zbus(name = "SetAirplaneMode")]
    fn set_airplane_mode(&self, on: bool) {
        self.0.lock().unwrap().push(format!("airplane {on}"));
    }
}

#[tokio::test]
async fn the_shells_services_back_the_adapters() {
    let bus = TestBus::start();
    let client = bus.connect().await;
    assert!(!marathon::present(&client), "no shell yet");

    let calls: Calls = Arc::default();
    let shell = bus.connect().await;
    let o = shell.object_server();
    o.at(
        "/org/marathonos/Shell/Alarm",
        Alarm(calls.clone(), Mutex::default()),
    )
    .await
    .unwrap();
    o.at("/org/marathonos/Shell/Settings", Settings)
        .await
        .unwrap();
    o.at("/org/marathonos/Shell/Contacts", Contacts)
        .await
        .unwrap();
    o.at("/org/marathonos/Shell/Telephony", Telephony(calls.clone()))
        .await
        .unwrap();
    o.at("/org/marathonos/Shell/Network", Network(calls.clone()))
        .await
        .unwrap();
    shell.request_name(marathon::SHELL).await.unwrap();
    shell.request_name("org.marathonos.Dav").await.unwrap();
    assert!(marathon::present(&client));

    let clock = ShellClock::new(client.clone());
    let cookie = clock.set_timer(600, None).await.unwrap();
    clock.set_alarm(7, 5, Some("Gym")).await.unwrap();
    let up = clock.upcoming().await.unwrap();
    assert_eq!(up.len(), 1);
    assert_eq!(
        (up[0].kind.as_str(), up[0].seconds, up[0].cookie),
        ("timer", Some(600), cookie)
    );
    assert!(clock.cancel(cookie).await.unwrap());
    assert!(!clock.cancel(cookie).await.unwrap());

    let cal = ShellCalendar {
        session: client.clone(),
    };
    // Friday 2 October 2026, for a week.
    let ev = cal
        .events(1_790_966_550, 1_790_966_550 + 8 * 86_400, 10)
        .unwrap();
    assert_eq!(ev.len(), 1);
    assert_eq!(ev[0].title, "Dentist");
    assert_eq!(ev[0].end - ev[0].start, 1800);

    let contacts = ShellContacts::new(client.clone());
    assert_eq!(contacts.names(), ["Anna Virtanen"]);
    let found = contacts.lookup("anna", 5).unwrap();
    assert_eq!(found[0].phones, ["+358401234567"]);
    assert!(found[0].emails.is_empty());

    let phone = ShellTelephony {
        session: client.clone(),
    };
    phone.dial("+358 40 123 4567").await.unwrap();
    assert!(phone.dial("call me").await.is_err());

    let radios = ShellToggles {
        session: client.clone(),
    };
    assert!(radios.get(Toggle::Wifi).await.unwrap());
    assert!(!radios.get(Toggle::FlightMode).await.unwrap());
    radios.set(Toggle::Wifi, false).await.unwrap();
    radios.set(Toggle::FlightMode, true).await.unwrap();
    assert!(
        radios.get(Toggle::MobileData).await.is_err(),
        "no modem object"
    );

    let calls = calls.lock().unwrap().clone();
    assert_eq!(
        calls,
        [
            "create \"\" Timer [] true",
            "create \"07:05\" Gym [] false",
            "dial +358401234567",
            "wifi off",
            "airplane true",
        ]
    );
}
