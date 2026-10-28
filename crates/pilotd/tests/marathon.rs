// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The Marathon adapters against a stand-in Marathon shell on a private
//! session bus (the method shapes of Marathon's shell/src/ipc/shellservices.h).

// zbus interfaces take their arguments by value.

#![allow(clippy::unwrap_used, clippy::let_underscore_must_use, reason = "tests")]
#![allow(
    clippy::needless_pass_by_value,
    clippy::unused_self,
    reason = "the stand-in services' D-Bus methods"
)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use marathon_rt::testing::PrivateBus;
use pilotd::adapters::marathon::{
    self, ShellCalendar, ShellClock, ShellContacts, ShellTelephony, ShellToggles,
};
use pilotd::adapters::{
    Calendar as _, Clock as _, Contacts as _, DeviceToggles as _, Telephony as _, Toggle,
};
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
    let Some(bus) = PrivateBus::start() else {
        return;
    };
    let client = bus.connect().await.unwrap();
    assert!(!marathon::present(&client), "no shell yet");

    let calls: Calls = Arc::default();
    let shell = bus.connect().await.unwrap();
    let o = shell.object_server();
    o.at(
        "/org/marathonos/Shell/Alarm",
        Alarm(Arc::clone(&calls), Mutex::default()),
    )
    .await
    .unwrap();
    o.at("/org/marathonos/Shell/Settings", Settings)
        .await
        .unwrap();
    o.at("/org/marathonos/Shell/Contacts", Contacts)
        .await
        .unwrap();
    o.at(
        "/org/marathonos/Shell/Telephony",
        Telephony(Arc::clone(&calls)),
    )
    .await
    .unwrap();
    o.at("/org/marathonos/Shell/Network", Network(Arc::clone(&calls)))
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

struct Navigation(Calls, u32);

#[zbus::interface(name = "org.marathonos.Shell.Navigation1")]
impl Navigation {
    #[zbus(name = "AppIdForPid")]
    fn app_id_for_pid(&self, pid: u32) -> String {
        self.0.lock().unwrap().push(format!("pid {pid}"));
        if pid == self.1 {
            "notes".into()
        } else {
            String::new()
        }
    }
}

/// A process to name: sleeps when run with `PILOTD_TEST_SLEEP` set.
#[test]
fn sleeper() {
    if let Some(secs) = std::env::var("PILOTD_TEST_SLEEP")
        .ok()
        .and_then(|s| s.parse().ok())
    {
        std::thread::sleep(std::time::Duration::from_secs(secs));
    }
}

#[tokio::test]
async fn the_shell_names_a_marathon_apps_process() {
    let dir = tempfile::tempdir().unwrap();
    // This test binary under the runner's name, running only `sleeper`:
    // a symlink to /bin/sleep exits at once where sleep is busybox, which
    // picks its applet by the name it is run as.
    let runner = dir.path().join("marathon-app-runner");
    std::os::unix::fs::symlink(std::env::current_exe().unwrap(), &runner).unwrap();
    let Some(bus) = PrivateBus::start() else {
        return;
    };
    let sleeping = || {
        std::process::Command::new(&runner)
            .args(["sleeper", "--exact", "--quiet"])
            .env("PILOTD_TEST_SLEEP", "30")
            .stdout(std::process::Stdio::null())
            .spawn()
            .unwrap()
    };
    let mut app = sleeping();
    let mut other = sleeping();

    let client = bus.connect().await.unwrap();
    let calls: Calls = Arc::default();
    let shell = bus.connect().await.unwrap();
    shell
        .object_server()
        .at(
            "/org/marathonos/Shell/Navigation",
            Navigation(Arc::clone(&calls), app.id()),
        )
        .await
        .unwrap();
    shell.request_name(marathon::SHELL).await.unwrap();

    let found = marathon::app_for_pid(&client, app.id()).await.unwrap();
    assert_eq!(
        (found.id.as_str(), found.name.as_str()),
        ("org.marathonos.notes", "Notes")
    );
    assert!(
        marathon::app_for_pid(&client, other.id()).await.is_none(),
        "not an app the shell runs"
    );
    assert!(
        marathon::app_for_pid(&client, std::process::id())
            .await
            .is_none(),
        "not a runner"
    );
    assert_eq!(
        calls.lock().unwrap().clone(),
        [format!("pid {}", app.id()), format!("pid {}", other.id())]
    );

    let _ = app.kill();
    let _ = other.kill();
    let _ = app.wait();
    let _ = other.wait();
}

struct Foreground(Arc<Mutex<String>>);

#[zbus::interface(name = "org.marathonos.Shell.Navigation1")]
impl Foreground {
    #[zbus(name = "GetForegroundApp")]
    fn get_foreground_app(&self) -> String {
        self.0.lock().unwrap().clone()
    }
}

#[tokio::test]
async fn the_shell_names_the_android_app_in_front() {
    let data = tempfile::tempdir().unwrap();
    std::fs::create_dir(data.path().join("applications")).unwrap();
    std::fs::write(
        data.path()
            .join("applications/deckard.org.example.chat.desktop"),
        "[Desktop Entry]\nType=Application\nName=Chat\nExec=/usr/libexec/deckard-launch app launch org.example.chat\n",
    )
    .unwrap();

    let Some(bus) = PrivateBus::start() else {
        return;
    };
    let client = bus.connect().await.unwrap();
    let shell = bus.connect().await.unwrap();
    let front = Arc::new(Mutex::new("deckard.org.example.chat".to_owned()));
    shell
        .object_server()
        .at(
            "/org/marathonos/Shell/Navigation",
            Foreground(Arc::clone(&front)),
        )
        .await
        .unwrap();
    shell.request_name(marathon::SHELL).await.unwrap();

    let found = marathon::android_in_front(&client, data.path())
        .await
        .unwrap();
    assert_eq!(
        (found.id.as_str(), found.name.as_str()),
        ("deckard.org.example.chat", "Chat")
    );

    for other in [
        "notes",
        "deckard.",
        "deckard.../x",
        "waydroid.org.example.chat",
        "",
    ] {
        *front.lock().unwrap() = other.to_owned();
        assert!(
            marathon::android_in_front(&client, data.path())
                .await
                .is_none(),
            "{other:?} is not an Android app"
        );
    }
}
