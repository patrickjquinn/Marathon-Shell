//! The shell's D-Bus services, `org.marathonos.Shell`, served from the I/O
//! thread: each backend exports its `<Name>1` interface at
//! `/org/marathonos/Shell/<Name>` when it starts, and calls into its `QObject`
//! on the GUI thread with `on_gui`.

use std::collections::HashMap;
use std::pin::Pin;

use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use serde::Serialize;
use zbus::message::Header;
use zbus::{fdo, object_server::Interface};
use zbus::{DynamicType, OwnedVariant as OwnedValue};

use crate::{gate, io, log};

pub const NAME: &str = "org.marathonos.Shell";
const MIGRATION_NAME: &str = "org.marathonos.Shell.Session";

/// What a service's `GetState` and `StateChanged` carry.
pub type State = HashMap<String, OwnedValue>;

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::ipc"]
    extern "Rust" {
        /// Takes `org.marathonos.Shell` once every service is exported.
        fn own_name();
    }
}

pub fn path(name: &str) -> String {
    format!("/org/marathonos/Shell/{name}")
}

/// Serves `iface` at `/org/marathonos/Shell/<name>`.
pub fn export<I: Interface>(name: &'static str, iface: I) {
    io::spawn(async move {
        let served = async {
            io::session_bus()
                .await?
                .object_server()
                .at(path(name), iface)
                .await
        };
        if let Err(e) = served.await {
            log::warn("ipc", format_args!("cannot serve {name}: {e}"));
        }
    });
}

static NAMED: async_lock::OnceCell<()> = async_lock::OnceCell::new();

fn own_name() {
    io::spawn(async {
        let bus = match io::session_bus().await {
            Ok(bus) => bus,
            Err(e) => return log::warn("ipc", format_args!("no session bus: {e}")),
        };
        if let Err(e) = bus.request_name(NAME).await {
            return log::warn("ipc", format_args!("cannot own {NAME}: {e}"));
        }
        // AppStore1 and Navigation1 briefly lived on this name during the
        // Rust migration. Keep the alias for mixed-version image updates.
        if let Err(e) = bus.request_name(MIGRATION_NAME).await {
            log::warn(
                "ipc",
                format_args!("cannot own migration alias {MIGRATION_NAME}: {e}"),
            );
        }
        NAMED.set(()).await.ok();
    });
}

/// Once the shell owns `org.marathonos.Shell`: the services that ask it
/// who their caller is answer the shell only then.
pub async fn named() {
    NAMED.wait().await;
}

/// Sends `<Name>1.<member>` from `/org/marathonos/Shell/<name>`, once the
/// shell owns its name: clients match the sender by it, so one sent before
/// would reach none of them.
pub fn signal<B>(name: &'static str, member: &'static str, body: B)
where
    B: Serialize + DynamicType + Send + Sync + 'static,
{
    io::spawn(async move {
        named().await;
        let Ok(bus) = io::session_bus().await else {
            return;
        };
        let interface = format!("{NAME}.{name}1");
        if let Err(e) = bus
            .emit_signal(
                None::<&str>,
                path(name).as_str(),
                interface.as_str(),
                member,
                &body,
            )
            .await
        {
            log::warn("ipc", format_args!("{name}.{member}: {e}"));
        }
    });
}

/// The app (or `service:<unit>`) behind this call, if any.
pub async fn caller(header: &Header<'_>) -> Option<String> {
    let sender = header.sender()?;
    let bus = io::session_bus().await.ok()?;
    let pid = fdo::DBusProxy::new(&bus)
        .await
        .ok()?
        .get_connection_unix_process_id(sender.clone().into())
        .await
        .ok();
    gate::caller(pid)
}

/// The caller of this call, when it may use any of `permissions` for `area`.
pub async fn admit(header: &Header<'_>, area: &str, permissions: &[&str]) -> fdo::Result<String> {
    let sender = header
        .sender()
        .ok_or_else(|| fdo::Error::AccessDenied("Unknown caller".into()))?;
    let bus = io::session_bus().await?;
    let pid = fdo::DBusProxy::new(&bus)
        .await?
        .get_connection_unix_process_id(sender.clone().into())
        .await
        .ok();
    let permissions: Vec<String> = permissions.iter().map(|p| (*p).to_owned()).collect();
    Ok(gate::admit(pid, sender.as_str(), area, &permissions)?)
}

/// `f`'s answer from `qt`'s object, on the GUI thread.
pub async fn on_gui<T, R>(
    qt: &CxxQtThread<T>,
    f: impl FnOnce(Pin<&mut T>) -> R + Send + 'static,
) -> fdo::Result<R>
where
    T: Threading + CxxQtType,
    R: Send + 'static,
{
    let (tx, rx) = async_channel::bounded(1);
    qt.queue(move |obj| {
        tx.try_send(f(obj)).ok();
    })
    .map_err(|_stopping| fdo::Error::Failed("the shell is stopping".into()))?;
    rx.recv()
        .await
        .map_err(|_stopping| fdo::Error::Failed("the shell is stopping".into()))
}

/// A `State` entry.
pub fn value(v: impl Into<zbus::Variant<'static>>) -> OwnedValue {
    OwnedValue::try_from(v.into()).unwrap_or_else(|_| OwnedValue::from(false))
}
