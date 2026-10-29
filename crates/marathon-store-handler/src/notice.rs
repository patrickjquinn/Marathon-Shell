//! An install's or update's row in the shell's Hub, over
//! org.freedesktop.Notifications: ongoing with flatpak's percent (the
//! "value" hint) while it runs, then "<App> installed", whose tap opens the
//! app. A failed or cancelled job leaves nothing; the shell drops the row
//! of a handler that stops without saying.

use std::collections::HashMap;

use zbus::blocking::Connection;
use zbus::zvariant::Value;

use crate::request::Verb;

// Reef, the store: tapping a running install opens it.
const STORE: &str = "shipwright-reef";

/// The running and the finished row's titles.
pub fn titles(verb: Verb, name: &str) -> (String, String) {
    if verb == Verb::Update {
        (format!("Updating {name}"), format!("{name} updated"))
    } else {
        (format!("Installing {name}"), format!("{name} installed"))
    }
}

pub struct Notice {
    bus: Option<Connection>,
    running: String,
    done: String,
    id: u32,
    shown: Option<i32>,
}

impl Notice {
    /// Uninstalls show nothing.
    pub fn for_job(verb: Verb, name: &str) -> Self {
        if verb == Verb::Uninstall {
            return Notice::none();
        }
        let (running, done) = titles(verb, name);
        let bus = Connection::session()
            .inspect_err(|e| warn(&format!("no session bus: {e}")))
            .ok();
        Notice {
            bus,
            running,
            done,
            id: 0,
            shown: None,
        }
    }

    pub fn none() -> Self {
        Notice {
            bus: None,
            running: String::new(),
            done: String::new(),
            id: 0,
            shown: None,
        }
    }

    /// Only a new percent reaches the shell; negative while unknown.
    pub fn progress(&mut self, percent: i32) {
        if self.shown == Some(percent) {
            return;
        }
        self.shown = Some(percent);
        let body = if percent < 0 {
            String::new()
        } else {
            format!("{percent}%")
        };
        let hints = HashMap::from([
            ("value", Value::from(percent)),
            ("desktop-entry", Value::from(STORE)),
            ("category", Value::from("transfer")),
        ]);
        let summary = self.running.clone();
        self.notify("download", &summary, &body, hints);
    }

    pub fn finish(&mut self, app_id: &str, icon: &str) {
        let hints = HashMap::from([("desktop-entry", Value::from(app_id))]);
        let summary = self.done.clone();
        self.notify(icon, &summary, "", hints);
    }

    pub fn close(&mut self) {
        let Some(bus) = &self.bus else { return };
        if self.id == 0 {
            return;
        }
        if let Err(e) = bus.call_method(
            Some("org.freedesktop.Notifications"),
            "/org/freedesktop/Notifications",
            Some("org.freedesktop.Notifications"),
            "CloseNotification",
            &(self.id,),
        ) {
            warn(&format!("CloseNotification: {e}"));
        }
    }

    fn notify(&mut self, icon: &str, summary: &str, body: &str, hints: HashMap<&str, Value>) {
        let Some(bus) = &self.bus else { return };
        let reply = bus
            .call_method(
                Some("org.freedesktop.Notifications"),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                "Notify",
                &(
                    STORE,
                    self.id,
                    icon,
                    summary,
                    body,
                    vec!["default", "Open"],
                    hints,
                    -1i32,
                ),
            )
            .and_then(|reply| reply.body().deserialize::<u32>());
        match reply {
            Ok(id) => self.id = id,
            // One warning, not one per redraw.
            Err(e) => {
                warn(&format!("Notify: {e}"));
                self.bus = None;
            }
        }
    }
}

#[allow(
    clippy::print_stderr,
    reason = "the handler's only diagnostics channel"
)]
fn warn(message: &str) {
    eprintln!("marathon-store-handler: {message}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn titles_name_the_app() {
        assert_eq!(
            titles(Verb::Install, "Maps"),
            ("Installing Maps".to_owned(), "Maps installed".to_owned())
        );
        assert_eq!(
            titles(Verb::Update, "Maps"),
            ("Updating Maps".to_owned(), "Maps updated".to_owned())
        );
    }
}
