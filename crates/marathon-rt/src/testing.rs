//! For the daemons' tests: a private session bus with a stand-in shell, and
//! the daemon under test running on it.

use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

use zbus::{fdo, interface, Connection};

/// A `dbus-daemon` of the test's own.
pub struct PrivateBus {
    bus: Child,
    daemon: Option<Child>,
    pub address: String,
}

impl PrivateBus {
    /// None where there is no `dbus-daemon`.
    pub fn start() -> Option<Self> {
        let mut bus = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .stdout(Stdio::piped())
            .spawn()
            .ok()?;
        let mut address = String::new();
        BufReader::new(bus.stdout.take()?)
            .read_line(&mut address)
            .ok()?;
        Some(Self {
            bus,
            daemon: None,
            address: address.trim().to_owned(),
        })
    }

    pub async fn connect(&self) -> zbus::Result<Connection> {
        zbus::connection::Builder::address(self.address.as_str())?
            .build()
            .await
    }

    /// The shell's `Permissions1`, admitting every caller but for `refused`.
    pub async fn shell(&self, refused: &[&str]) -> zbus::Result<Connection> {
        let shell = Shell(refused.iter().map(|&p| p.to_owned()).collect());
        zbus::connection::Builder::address(self.address.as_str())?
            .name("org.marathonos.Shell")?
            .serve_at("/org/marathonos/Shell/Permissions", shell)?
            .build()
            .await
    }

    /// Runs `exe` on this bus with `home` as its home, until it owns `name`.
    pub async fn run(&mut self, exe: &str, home: &Path, name: &str) -> zbus::Result<()> {
        let daemon = Command::new(exe)
            .env("DBUS_SESSION_BUS_ADDRESS", &self.address)
            .env("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent")
            .env("HOME", home)
            .env("XDG_DATA_HOME", home.join("data"))
            .env("XDG_CACHE_HOME", home.join("cache"))
            .env("XDG_CONFIG_HOME", home.join("config"))
            .spawn()
            .map_err(|e| zbus::Error::Failure(e.to_string()))?;
        self.daemon = Some(daemon);
        let dbus = fdo::DBusProxy::new(&self.connect().await?).await?;
        for _ in 0..100 {
            if dbus.name_has_owner(name.try_into()?).await? {
                return Ok(());
            }
            async_io::Timer::after(Duration::from_millis(50)).await;
        }
        Err(zbus::Error::Failure(format!("{exe} never took {name}")))
    }
}

impl Drop for PrivateBus {
    fn drop(&mut self) {
        for child in self.daemon.iter_mut().chain([&mut self.bus]) {
            child.kill().ok();
            child.wait().ok();
        }
    }
}

struct Shell(Vec<String>);

#[interface(name = "org.marathonos.Shell.Permissions1")]
#[allow(
    clippy::needless_pass_by_value,
    reason = "the method's D-Bus arguments"
)]
impl Shell {
    fn admit(&self, sender: &str, area: &str, permissions: Vec<String>) -> fdo::Result<()> {
        match permissions.iter().find(|p| self.0.contains(p)) {
            Some(p) => {
                crate::log::warn(area, format_args!("{sender} refused {p}"));
                Err(fdo::Error::AccessDenied(format!("Missing permission: {p}")))
            }
            None => Ok(()),
        }
    }
}
