//! The systemd user manager, as the shell calls it.

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

    fn set_unit_properties(
        &self,
        name: &str,
        runtime: bool,
        properties: &[(&str, Value<'_>)],
    ) -> zbus::Result<()>;

    fn freeze_unit(&self, name: &str) -> zbus::Result<()>;

    fn thaw_unit(&self, name: &str) -> zbus::Result<()>;

    fn unset_and_set_environment(
        &self,
        names: &[String],
        assignments: &[String],
    ) -> zbus::Result<()>;
}
