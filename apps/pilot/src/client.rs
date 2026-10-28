// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The UI's side of `org.shipwright.Pilot1` (shoal/pilot/README.md, "D-Bus
//! interface"). Blocking zbus: each call runs on the caller's thread, which
//! for turns is a worker (see `bridge`). Structured values stay JSON
//! strings end to end; QML parses them.

use std::time::Duration;

use zbus::blocking::{Connection, Proxy};

pub const BUS_NAME: &str = "org.shipwright.Pilot";
pub const PATH: &str = "/org/shipwright/Pilot";
pub const INTERFACE: &str = "org.shipwright.Pilot1";

/// A turn can include several model rounds; D-Bus' default 25 s is short.
const TURN_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone)]
pub struct Client {
    conn: Connection,
}

/// A change pilotd announced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Change {
    Offline(bool),
    LastResponse(String),
    /// Pilot's Events view entry was tapped (`OpenEvents`).
    EventsRequested,
    /// The system-wide gesture asked for the sheet (`ShowSheet`).
    SheetRequested,
}

fn err(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(_, Some(msg), _) => msg.clone(),
        other => other.to_string(),
    }
}

impl Client {
    /// Connects to the session bus. Calls activate pilotd if it is not
    /// running.
    pub fn connect() -> Result<Client, String> {
        let conn = zbus::blocking::connection::Builder::session()
            .map(|b| b.method_timeout(TURN_TIMEOUT))
            .and_then(zbus::blocking::connection::Builder::build)
            .map_err(|e| err(&e))?;
        Ok(Client { conn })
    }

    fn proxy(&self) -> Result<Proxy<'static>, String> {
        Proxy::new(&self.conn, BUS_NAME, PATH, INTERFACE).map_err(|e| err(&e))
    }

    fn call<B, R>(&self, method: &str, body: &B) -> Result<R, String>
    where
        B: serde::Serialize + zbus::zvariant::DynamicType,
        R: for<'d> zbus::zvariant::DynamicDeserialize<'d>,
    {
        self.proxy()?.call(method, body).map_err(|e| err(&e))
    }

    pub fn ask(&self, text: &str, spoken: bool) -> Result<String, String> {
        self.call("Ask", &(text, spoken))
    }

    pub fn confirm(&self, id: &str, approved: bool) -> Result<String, String> {
        self.call("Confirm", &(id, approved))
    }

    pub fn settings(&self) -> Result<String, String> {
        self.call("Settings", &())
    }

    pub fn set_consent(&self, name: &str, on: bool) -> Result<(), String> {
        self.call("SetConsent", &(name, on))
    }

    pub fn open_url(&self, url: &str) -> Result<bool, String> {
        self.call("OpenUrl", &(url,))
    }

    pub fn clear_conversation(&self) -> Result<(), String> {
        self.call("ClearConversation", &())
    }

    pub fn clear_on_screen(&self) -> Result<(), String> {
        self.call("ClearOnScreen", &())
    }

    pub fn take_launch_request(&self) -> Result<String, String> {
        self.call("TakeLaunchRequest", &())
    }

    pub fn capabilities(&self) -> Result<String, String> {
        self.call("Capabilities", &())
    }

    pub fn memories(&self) -> Result<String, String> {
        self.call("Memories", &())
    }

    pub fn forget(&self, id: i64) -> Result<bool, String> {
        self.call("Forget", &(id,))
    }

    pub fn set_guide(&self, step: &str, done: bool) -> Result<(), String> {
        self.call("SetGuide", &(step, done))
    }

    pub fn set_name(&self, name: &str) -> Result<(), String> {
        self.call("SetName", &(name,))
    }

    /// Tells pilotd the person's locale (`de_DE`).
    pub fn set_locale(&self, name: &str) -> Result<(), String> {
        self.call("SetLocale", &(name,))
    }

    pub fn set_backend(&self, name: &str) -> Result<(), String> {
        self.call("SetBackend", &(name,))
    }

    pub fn egress_log(&self, limit: u32) -> Result<String, String> {
        self.call("EgressLog", &(limit,))
    }

    pub fn export(&self) -> Result<String, String> {
        self.call("Export", &())
    }

    pub fn wipe(&self) -> Result<(), String> {
        self.call("Wipe", &())
    }

    /// Bytes of the downloaded speech models.
    pub fn voice_models(&self) -> Result<u64, String> {
        self.call("VoiceModels", &())
    }

    /// Deletes the downloaded speech models; the bytes freed.
    pub fn remove_voice_models(&self) -> Result<u64, String> {
        self.call("RemoveVoiceModels", &())
    }

    /// Triage results for the Events list, newest first; `[]` when this
    /// pilotd has none.
    pub fn triage(&self) -> String {
        self.call::<_, String>("Triage", &(100u32,))
            .unwrap_or_else(|_| "[]".into())
    }

    /// A camera turn: the question and the prepared photo's bytes.
    pub fn look(&self, question: &str, jpeg: &[u8]) -> Result<String, String> {
        self.call("Look", &(question, jpeg))
    }

    /// A push-to-talk turn through pilot-voice; the `TurnResult` JSON.
    pub fn listen(&self) -> Result<String, String> {
        self.call("Listen", &())
    }

    pub fn offline(&self) -> Result<bool, String> {
        self.proxy()?.get_property("Offline").map_err(|e| err(&e))
    }

    pub fn last_response(&self) -> Result<String, String> {
        self.proxy()?
            .get_property("LastResponse")
            .map_err(|e| err(&e))
    }

    pub fn now(&self) -> Result<String, String> {
        self.call("Now", &())
    }

    pub fn cancel_clock(&self, cookie: u32) -> Result<bool, String> {
        self.call("CancelClock", &(cookie,))
    }

    pub fn extend_timer(&self, cookie: u32, seconds: u32) -> Result<String, String> {
        self.call("ExtendTimer", &(cookie, seconds))
    }

    /// Calls `on_stage` with each `TurnProgress` JSON until the bus
    /// connection ends or `on_stage` returns false.
    pub fn watch_progress(&self, mut on_stage: impl FnMut(String) -> bool) -> Result<(), String> {
        let stages = self
            .proxy()?
            .receive_signal("TurnProgress")
            .map_err(|e| err(&e))?;
        for m in stages {
            let Ok(stage) = m.body().deserialize::<String>() else {
                continue;
            };
            if !on_stage(stage) {
                break;
            }
        }
        Ok(())
    }

    /// Calls `on_change` for every `Offline` or `LastResponse` change until
    /// the bus connection ends or `on_change` returns false.
    pub fn watch(&self, mut on_change: impl FnMut(Change) -> bool) -> Result<(), String> {
        let props = zbus::blocking::fdo::PropertiesProxy::builder(&self.conn)
            .destination(BUS_NAME)
            .and_then(|b| b.path(PATH))
            .and_then(zbus::blocking::proxy::Builder::build)
            .map_err(|e| err(&e))?;
        let changes = props.receive_properties_changed().map_err(|e| err(&e))?;
        for signal in changes {
            let Ok(args) = signal.args() else { continue };
            if args.interface_name().as_str() != INTERFACE {
                continue;
            }
            for (name, value) in args.changed_properties() {
                let change = match *name {
                    "Offline" => bool::try_from(value).ok().map(Change::Offline),
                    "LastResponse" => <&str>::try_from(value)
                        .ok()
                        .map(|s| Change::LastResponse(s.to_owned())),
                    "EventsRequested" => Some(Change::EventsRequested),
                    "SheetRequested" => Some(Change::SheetRequested),
                    _ => None,
                };
                if let Some(c) = change {
                    if !on_change(c) {
                        return Ok(());
                    }
                }
            }
        }
        Ok(())
    }
}
