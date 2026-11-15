// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Who may call `org.shipwright.Pilot1`. On Marathon only the Pilot app (a
//! process in its `marathon-app-shoal-pilot` cgroup, where the shell's
//! lifecycle puts it, as the shell's own `gate` reads it; without app
//! cgroups, the process the shell launched for it or one below it) and the
//! shell (the process that owns `org.marathonos.Shell`) may: anything else on
//! the session bus could otherwise ask for a text or a call and say yes to
//! its own card, or read the memories and logs. Elsewhere Sailjail's
//! `ShoalPilot` permission decides, before a call reaches pilotd.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use zbus::fdo;
use zbus::names::BusName;

use crate::adapters::marathon::SHELL;

/// The Pilot app's id in the shell (its cgroup, `marathon-app-<id>`).
pub const PILOT_APP: &str = "shoal-pilot";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Caller {
    Shell,
    Pilot,
    /// No check (not Marathon).
    Unchecked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Policy {
    #[default]
    Any,
    Marathon,
}

#[derive(Default)]
pub struct Callers {
    pub policy: Policy,
    /// Admitted connections: a unique name is never given out twice.
    admitted: Mutex<HashMap<String, Caller>>,
}

impl Callers {
    pub fn new(policy: Policy) -> Callers {
        Callers {
            policy,
            admitted: Mutex::default(),
        }
    }

    /// The caller behind `sender`, or `AccessDenied`.
    pub async fn admit(
        &self,
        conn: &zbus::Connection,
        sender: Option<&str>,
    ) -> fdo::Result<Caller> {
        if self.policy == Policy::Any {
            return Ok(Caller::Unchecked);
        }
        let denied = || fdo::Error::AccessDenied("only Pilot and the shell may ask Pilot".into());
        let sender = sender.ok_or_else(denied)?;
        if let Some(c) = self.admitted().get(sender) {
            return Ok(*c);
        }
        let caller = identify(conn, sender).await.ok_or_else(|| {
            log::warn!("refused a call from {sender}: neither Pilot nor the shell");
            denied()
        })?;
        let mut admitted = self.admitted();
        if admitted.len() > 64 {
            admitted.clear();
        }
        admitted.insert(sender.to_owned(), caller);
        Ok(caller)
    }

    fn admitted(&self) -> std::sync::MutexGuard<'_, HashMap<String, Caller>> {
        self.admitted
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

async fn pid_of(dbus: &fdo::DBusProxy<'_>, name: &str) -> Option<u32> {
    let name = BusName::try_from(name).ok()?;
    dbus.get_connection_unix_process_id(name).await.ok()
}

/// The shell moves an app it starts into the app's cgroup just after the
/// process starts, so a first call can come before that: a caller in no
/// app's cgroup is looked at again for a moment.
async fn identify(conn: &zbus::Connection, sender: &str) -> Option<Caller> {
    let dbus = fdo::DBusProxy::new(conn).await.ok()?;
    let pid = pid_of(&dbus, sender).await?;
    for _ in 0..4 {
        if pid_of(&dbus, SHELL).await == Some(pid) {
            return Some(Caller::Shell);
        }
        let cgroup = std::fs::read_to_string(format!("/proc/{pid}/cgroup")).ok()?;
        match app_of_cgroup(&cgroup) {
            Some(app) if app == PILOT_APP => return Some(Caller::Pilot),
            Some(_) => return None,
            None if launched_app(conn, pid).await.as_deref() == Some(PILOT_APP) => {
                return Some(Caller::Pilot);
            }
            None => {
                async_io::Timer::after(Duration::from_millis(250)).await;
            }
        }
    }
    None
}

/// The app the shell launched `pid` or one of its parents for (a Keel host
/// or a sandbox runs the app below the process it started).
async fn launched_app(conn: &zbus::Connection, pid: u32) -> Option<String> {
    let mut cursor = Some(pid);
    for _ in 0..8 {
        let p = cursor.filter(|&p| p > 1)?;
        let id = crate::adapters::marathon::app_id_for_pid(conn, p)
            .await
            .ok()?;
        if !id.is_empty() {
            return Some(id);
        }
        cursor = parent(&std::fs::read_to_string(format!("/proc/{p}/stat")).ok()?);
    }
    None
}

/// The parent in a `/proc/<pid>/stat` line (after the command in parentheses).
fn parent(stat: &str) -> Option<u32> {
    stat.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(1)?
        .parse()
        .ok()
}

/// The app a `/proc/<pid>/cgroup` text puts the process in
/// (`marathon-app-<id>`), if any.
pub fn app_of_cgroup(cgroup: &str) -> Option<&str> {
    cgroup
        .lines()
        .filter_map(|l| l.strip_prefix("0::"))
        .flat_map(|path| path.split('/'))
        .find_map(|c| c.strip_prefix("marathon-app-"))
        .filter(|id| !id.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_app_is_read_from_its_cgroup() {
        let pilot = "0::/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-shoal-pilot\n";
        assert_eq!(app_of_cgroup(pilot), Some(PILOT_APP));
        assert_eq!(
            app_of_cgroup("0::/user.slice/marathon-apps/marathon-app-shoal-pilot-x\n"),
            Some("shoal-pilot-x")
        );
        assert_eq!(
            app_of_cgroup("0::/user.slice/marathon-apps/marathon-app-notes\n"),
            Some("notes")
        );
        assert_eq!(
            app_of_cgroup("0::/user.slice/user@1000.service/app.slice/marathon-shell.service\n"),
            None
        );
        assert_eq!(
            app_of_cgroup("1:name=systemd:/marathon-app-shoal-pilot\n"),
            None
        );
    }

    #[test]
    fn the_parent_is_read_past_the_command() {
        assert_eq!(
            parent("4242 (shoal pilot) S 4100 4242 4242 0 -1"),
            Some(4100)
        );
        assert_eq!(parent("1 (a) b) S 0 1"), Some(0));
        assert_eq!(parent("garbage"), None);
    }
}
