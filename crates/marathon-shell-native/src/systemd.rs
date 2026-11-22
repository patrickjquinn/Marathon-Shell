//! The systemd user manager, as the shell calls it, and the system manager
//! it asks about units.

use futures_lite::StreamExt as _;
use zbus::{OwnedObjectPath, Variant as Value};

#[zbus::proxy(
    interface = "org.freedesktop.systemd1.Manager",
    default_service = "org.freedesktop.systemd1",
    default_path = "/org/freedesktop/systemd1"
)]
pub trait SystemdManager {
    fn start_transient_unit(
        &self,
        name: &str,
        mode: &str,
        properties: &[(&str, Value<'_>)],
        aux: &[(&str, &[(&str, Value<'_>)])],
    ) -> zbus::Result<OwnedObjectPath>;

    fn stop_unit(&self, name: &str, mode: &str) -> zbus::Result<OwnedObjectPath>;

    fn subscribe(&self) -> zbus::Result<()>;

    #[zbus(signal)]
    fn job_removed(
        &self,
        id: u32,
        job: OwnedObjectPath,
        unit: String,
        result: String,
    ) -> zbus::Result<()>;

    fn set_unit_properties(
        &self,
        name: &str,
        runtime: bool,
        properties: &[(&str, Value<'_>)],
    ) -> zbus::Result<()>;

    fn freeze_unit(&self, name: &str) -> zbus::Result<()>;

    fn thaw_unit(&self, name: &str) -> zbus::Result<()>;

    fn get_unit_file_state(&self, file: &str) -> zbus::Result<String>;

    fn unset_and_set_environment(
        &self,
        names: &[String],
        assignments: &[String],
    ) -> zbus::Result<()>;
}

/// Stops the graphical session and waits for it: the services `PartOf` it
/// (the X11 bridge, the portals) leave while the compositor still serves
/// them, rather than losing it under them.
pub(crate) async fn end_graphical_session() -> zbus::Result<()> {
    let manager = SystemdManagerProxy::new(&crate::io::session_bus().await?).await?;
    manager.subscribe().await?;
    let mut removed = manager.receive_job_removed().await?;
    let job = manager
        .stop_unit("graphical-session.target", "replace")
        .await?;
    while let Some(signal) = removed.next().await {
        if signal.args()?.job == job {
            break;
        }
    }
    Ok(())
}
