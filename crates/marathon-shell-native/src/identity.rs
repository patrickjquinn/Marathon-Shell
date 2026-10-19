//! Who is calling: the PID behind each session-bus connection, learnt as the
//! connection appears, so the shell's IPC reads a cache instead of asking
//! the bus daemon while a call waits on the GUI thread.

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex, PoisonError};

use futures_lite::StreamExt;
use zbus::fdo::DBusProxy;
use zbus::names::BusName;

use crate::{io, log};

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::identity"]
    extern "Rust" {
        /// Starts following the session bus's connections on the I/O thread.
        fn watch_session_bus();
        /// The PID behind a unique or well-known session-bus name; -1 while
        /// unknown.
        fn pid_of(name: &str) -> i64;
        /// A PID the caller learnt itself, for the next call.
        fn remember(name: &str, pid: u32);
    }
}

#[derive(Default)]
struct Names {
    // Unique name to PID.
    pids: HashMap<String, u32>,
    // Well-known name to its owner's unique name.
    owners: HashMap<String, String>,
}

// Written on the I/O thread, read on the GUI thread; held for a map lookup.
static NAMES: LazyLock<Mutex<Names>> = LazyLock::new(Mutex::default);

fn names() -> std::sync::MutexGuard<'static, Names> {
    NAMES.lock().unwrap_or_else(PoisonError::into_inner)
}

fn pid_of(name: &str) -> i64 {
    let names = names();
    let unique = if name.starts_with(':') { Some(name) } else { names.owners.get(name).map(String::as_str) };
    unique.and_then(|u| names.pids.get(u)).map_or(-1, |&pid| i64::from(pid))
}

fn remember(name: &str, pid: u32) {
    names().pids.insert(name.to_owned(), pid);
}

fn watch_session_bus() {
    io::spawn(async {
        if let Err(e) = watch().await {
            log::warn("identity", format_args!("not following the session bus: {e}"));
        }
    });
}

async fn watch() -> zbus::Result<()> {
    let bus = io::session_bus().await?;
    let dbus = DBusProxy::new(&bus).await?;
    // Subscribed before listing, so no connection falls between the two.
    let mut changes = dbus.receive_name_owner_changed().await?;
    for name in dbus.list_names().await? {
        let owner = if name.starts_with(':') { None } else { dbus.get_name_owner(name.inner().clone()).await.ok() };
        learn(&dbus, name.as_str(), owner.as_deref().map(zbus::names::UniqueName::as_str)).await;
    }
    while let Some(signal) = changes.next().await {
        let Ok(args) = signal.args() else { continue };
        learn(&dbus, args.name().as_str(), args.new_owner().as_ref().map(zbus::names::UniqueName::as_str)).await;
    }
    Ok(())
}

/// `name` now belongs to `owner`, or to no one.
async fn learn(dbus: &DBusProxy<'_>, name: &str, owner: Option<&str>) {
    if !name.starts_with(':') {
        let mut names = names();
        match owner {
            Some(owner) => names.owners.insert(name.to_owned(), owner.to_owned()),
            None => names.owners.remove(name),
        };
        return;
    }
    if owner.is_none() {
        names().pids.remove(name);
        return;
    }
    let Ok(bus_name) = BusName::try_from(name) else { return };
    if let Ok(pid) = dbus.get_connection_unix_process_id(bus_name).await {
        remember(name, pid);
    }
}

#[cfg(test)]
mod tests {
    use super::{names, pid_of, remember};

    #[test]
    fn well_known_names_resolve_through_their_owner() {
        remember(":1.900", 4242);
        names().owners.insert("org.example.Player".to_owned(), ":1.900".to_owned());
        assert_eq!(pid_of(":1.900"), 4242);
        assert_eq!(pid_of("org.example.Player"), 4242);
        assert_eq!(pid_of(":1.901"), -1);
        assert_eq!(pid_of("org.example.Gone"), -1);
    }
}
