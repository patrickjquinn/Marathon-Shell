//! A sandboxed app's buses: an xdg-dbus-proxy per sandbox, between the app
//! and the session and system buses, that lets it reach only the names its
//! policy lists and own only its own. Services see the proxy's pid, which
//! the shell knows as the app's ([`crate::gate::remember_pid`]) and moves
//! into the app's cgroup with the app.
//!
//! The sandbox sees `$XDG_RUNTIME_DIR/marathon-bus/<instance>`, where the
//! proxy listens (`bus`, `system_bus_socket`). A pool spare starts before
//! its app is known, so it has a proxy of its own (`spare`) that reaches
//! only dconf's writer, for the one connection its warm-up makes (dconf's,
//! which never reconnects); its app's proxy starts when it is adopted, and
//! every later connection goes there.

use std::fs;
use std::io::{self, Read as _};
use std::os::fd::{AsRawFd as _, OwnedFd};
use std::os::unix::fs::{DirBuilderExt as _, PermissionsExt as _};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::log;

const SHELL: &str = "org.marathonos.Shell";
const NGF: &str = "com.nokia.NonGraphicFeedback1.Backend";
const READY_MS: i32 = 2000;

/// Inside the sandbox: the proxy's directory, and the paths clients use.
pub(crate) const SANDBOX_DIR: &str = "marathon-bus";
pub(crate) const SESSION_SOCKET: &str = "bus";
pub(crate) const SYSTEM_SOCKET: &str = "system_bus_socket";
pub(crate) const SPARE_SOCKET: &str = "spare";
const DCONF: &str = "ca.desrt.dconf";

/// What an app's policy is made from.
#[derive(Debug, Default)]
pub(crate) struct Policy<'a> {
    pub app_id: &'a str,
    pub permissions: &'a [String],
    /// The manifest's `dbus` names: an OS app's only.
    pub names: Option<&'a marathon_apps::apps::BusNames>,
}

impl Policy<'_> {
    fn has(&self, permission: &str) -> bool {
        self.permissions.iter().any(|p| p == permission)
    }

    /// Every app reaches the shell (whose services check the caller),
    /// notifications, dconf's writer and the share service, and owns its
    /// runner's and its Keel actions' names.
    pub(crate) fn session(&self) -> Vec<String> {
        let mut rules: Vec<String> = [
            SHELL,
            "org.freedesktop.Notifications",
            DCONF,
            "org.sailfishos.share",
        ]
        .iter()
        .map(|n| format!("--talk={n}"))
        .collect();
        let mut talk = |name: &str| rules.push(format!("--talk={name}"));
        if self.has("telephony") || self.has("sms") {
            talk("org.marathonos.Telephony");
        }
        if self.has("contacts") || self.has("system") {
            talk("org.marathonos.Dav");
        }
        if self.has("storage") {
            talk("org.marathonos.MediaLibrary");
        }
        if let Some(names) = self.names {
            for name in names.talk.iter().filter(|n| valid_name(n)) {
                talk(name);
            }
        }
        rules.push(format!("--own={}", crate::tasks::runner_name(self.app_id)));
        let actions = format!("org.marathonos.{}", self.app_id);
        if valid_app_id(self.app_id) {
            rules.push(format!("--own={actions}"));
        }
        if let Some(names) = self.names {
            for name in names.own.iter().filter(|n| valid_name(n)) {
                rules.push(format!("--own={name}"));
            }
        }
        rules
    }

    /// Feedback (Silica's pulley menus and buttons play through the
    /// shell's NGF) for every app, the battery's history for Settings,
    /// `GeoClue` for an app with "location".
    pub(crate) fn system(&self) -> Vec<String> {
        let mut names = vec![NGF];
        if self.has("system") {
            names.push("org.freedesktop.UPower");
        }
        if self.has("location") {
            names.push("org.freedesktop.GeoClue2");
        }
        names.iter().map(|n| format!("--talk={n}")).collect()
    }
}

/// An app id as the manifest schema allows it: lower case, so its
/// `org.marathonos.<id>` never names a platform service.
fn valid_app_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id.split('.').all(|part| {
            part.starts_with(|c: char| c.is_ascii_lowercase())
                && part
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "_-".contains(c))
        })
}

/// A well-known name, with no wildcard and nothing a command line could
/// read as another option.
fn valid_name(name: &str) -> bool {
    name.len() <= 255
        && name.contains('.')
        && name.split('.').all(|part| {
            !part.is_empty()
                && !part.starts_with(|c: char| c.is_ascii_digit())
                && part
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_-".contains(c))
        })
        && !name.starts_with('-')
}

fn runtime() -> PathBuf {
    PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into()))
}

/// Where the proxy of sandbox `instance` listens.
pub(crate) fn dir(instance: &str) -> PathBuf {
    runtime().join(SANDBOX_DIR).join(instance)
}

/// The proxy's directory, made empty and private for the sandbox to bind.
pub(crate) fn prepare(instance: &str) -> io::Result<PathBuf> {
    let parent = runtime().join(SANDBOX_DIR);
    fs::DirBuilder::new()
        .mode(0o700)
        .recursive(true)
        .create(&parent)?;
    fs::set_permissions(&parent, fs::Permissions::from_mode(0o700))?;
    let dir = dir(instance);
    fs::DirBuilder::new().mode(0o700).create(&dir)?;
    Ok(dir)
}

/// A previous shell's proxies ended with it: their directories go.
pub(crate) fn remove_all() {
    fs::remove_dir_all(runtime().join(SANDBOX_DIR)).ok();
}

/// The sandbox closed: its sockets go.
pub(crate) fn remove(instance: &str) {
    if !instance.is_empty() {
        fs::remove_dir_all(dir(instance)).ok();
    }
}

fn address(variable: &str, fallback: &Path) -> String {
    std::env::var(variable)
        .ok()
        .filter(|a| !a.is_empty())
        .unwrap_or_else(|| format!("unix:path={}", fallback.display()))
}

fn arguments(policy: &Policy<'_>, dir: &Path, session: &str, system: &str) -> Vec<String> {
    let socket = |name| dir.join(name).to_string_lossy().into_owned();
    let mut args = vec![
        session.to_owned(),
        socket(SESSION_SOCKET),
        "--filter".to_owned(),
    ];
    args.extend(policy.session());
    args.extend([
        system.to_owned(),
        socket(SYSTEM_SOCKET),
        "--filter".to_owned(),
    ]);
    args.extend(policy.system());
    args
}

/// A running proxy. Dropping it closes the descriptor the proxy watches,
/// and the proxy exits; so does the shell's exit. Its pid names the app
/// until then.
pub(crate) struct BusProxy {
    pub app_id: String,
    pub pid: i64,
    _alive: OwnedFd,
}

impl BusProxy {
    /// A spare's proxy now speaks for the app the spare became.
    pub(crate) fn adopt(&mut self, app_id: &str) {
        app_id.clone_into(&mut self.app_id);
        crate::gate::remember_pid(self.pid, app_id);
    }
}

/// A pool spare's own proxy, which reaches dconf's writer only.
pub(crate) fn start_spare(instance: &str) -> io::Result<BusProxy> {
    let dir = prepare(instance)?;
    spawn(
        "",
        &[
            session_address(),
            dir.join(SPARE_SOCKET).to_string_lossy().into_owned(),
            "--filter".to_owned(),
            format!("--talk={DCONF}"),
        ],
    )
}

fn session_address() -> String {
    address("DBUS_SESSION_BUS_ADDRESS", &runtime().join("bus"))
}

/// The proxy for `policy`'s app in sandbox `instance`, once it listens.
pub(crate) fn start(policy: &Policy<'_>, instance: &str) -> io::Result<BusProxy> {
    let dir = dir(instance);
    if !dir.is_dir() {
        prepare(instance)?;
    }
    let system = address(
        "DBUS_SYSTEM_BUS_ADDRESS",
        Path::new("/run/dbus/system_bus_socket"),
    );
    spawn(
        policy.app_id,
        &arguments(policy, &dir, &session_address(), &system),
    )
}

/// The proxy for `app_id` ("" for a spare's), once it listens.
fn spawn(app_id: &str, arguments: &[String]) -> io::Result<BusProxy> {
    let (alive, ready) = pipe()?;
    // Its end of the pipe as its stdout: with no pre-exec hook, the child
    // is spawned rather than forked from the whole shell, which on the Q25
    // cost a launch tens of milliseconds.
    let mut command = Command::new("xdg-dbus-proxy");
    command
        .arg("--fd=1")
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::from(ready))
        .stderr(Stdio::inherit());
    let mut child = command.spawn()?;
    // Without our copy of its end, a proxy that dies is seen at once.
    drop(command);
    if let Err(e) = wait_ready(&alive) {
        child.kill().ok();
        child.wait().ok();
        return Err(e);
    }
    let pid = i64::from(child.id());
    let app_id = app_id.to_owned();
    if !app_id.is_empty() {
        crate::gate::remember_pid(pid, &app_id);
    }
    std::thread::spawn(move || {
        let status = child.wait();
        crate::gate::forget_pid(pid);
        if let Ok(status) = status {
            if !status.success() {
                log::warn("bus-proxy", format_args!("bus proxy {pid} ended: {status}"));
            }
        }
    });
    Ok(BusProxy {
        app_id,
        pid,
        _alive: alive,
    })
}

/// Our end and the proxy's: the proxy writes a byte to its end once it
/// listens, and exits when ours closes.
fn pipe() -> io::Result<(OwnedFd, OwnedFd)> {
    let mut fds = [0; 2];
    // SAFETY: pipe2 fills both descriptors, which we then own.
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: both are open and owned by nothing else.
    unsafe {
        use std::os::fd::FromRawFd as _;
        Ok((OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])))
    }
}

fn wait_ready(ours: &OwnedFd) -> io::Result<()> {
    let mut poll = libc::pollfd {
        fd: ours.as_raw_fd(),
        events: libc::POLLIN,
        revents: 0,
    };
    // SAFETY: one valid pollfd.
    let n = unsafe { libc::poll(&raw mut poll, 1, READY_MS) };
    if n < 0 {
        return Err(io::Error::last_os_error());
    }
    if n == 0 {
        return Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "the bus proxy did not start",
        ));
    }
    let mut byte = [0u8; 1];
    match fs::File::from(ours.try_clone()?).read(&mut byte)? {
        1 => Ok(()),
        _ => Err(io::Error::new(
            io::ErrorKind::BrokenPipe,
            "the bus proxy exited",
        )),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use marathon_apps::apps::BusNames;

    fn perms(list: &[&str]) -> Vec<String> {
        list.iter().map(|p| (*p).to_owned()).collect()
    }

    #[test]
    fn every_app_reaches_the_platform_and_owns_only_its_names() {
        let none = perms(&[]);
        let rules = Policy {
            app_id: "notes",
            permissions: &none,
            names: None,
        }
        .session();
        assert_eq!(
            rules,
            [
                "--talk=org.marathonos.Shell",
                "--talk=org.freedesktop.Notifications",
                "--talk=ca.desrt.dconf",
                "--talk=org.sailfishos.share",
                "--own=org.marathonos.AppRunner.notes",
                "--own=org.marathonos.notes",
            ]
        );
        assert!(!rules.iter().any(|r| r.contains("systemd1")));
    }

    #[test]
    fn permissions_add_the_services_behind_them() {
        let messages = perms(&["sms", "contacts", "storage"]);
        let rules = Policy {
            app_id: "messages",
            permissions: &messages,
            names: None,
        }
        .session();
        for name in [
            "org.marathonos.Telephony",
            "org.marathonos.Dav",
            "org.marathonos.MediaLibrary",
        ] {
            assert!(rules.contains(&format!("--talk={name}")), "{name}");
        }
        let none = perms(&[]);
        let plain = Policy {
            app_id: "calculator",
            permissions: &none,
            names: None,
        };
        assert!(!plain.session().iter().any(|r| r.contains("Telephony")));
        assert_eq!(
            plain.system(),
            ["--talk=com.nokia.NonGraphicFeedback1.Backend"]
        );
        let settings = perms(&["system", "location"]);
        let system = Policy {
            app_id: "settings",
            permissions: &settings,
            names: None,
        }
        .system();
        assert!(system.contains(&"--talk=org.freedesktop.UPower".to_owned()));
        assert!(system.contains(&"--talk=org.freedesktop.GeoClue2".to_owned()));
    }

    #[test]
    fn manifest_names_are_taken_only_as_plain_names() {
        let names = BusNames {
            talk: vec![
                "org.marathonos.Mail".into(),
                "org.freedesktop.*".into(),
                "--talk=org.freedesktop.systemd1".into(),
                "noDots".into(),
            ],
            own: vec!["org.mpris.MediaPlayer2.music".into(), "org.*".into()],
        };
        let none = perms(&[]);
        let rules = Policy {
            app_id: "email",
            permissions: &none,
            names: Some(&names),
        }
        .session();
        assert!(rules.contains(&"--talk=org.marathonos.Mail".to_owned()));
        assert!(rules.contains(&"--own=org.mpris.MediaPlayer2.music".to_owned()));
        assert!(!rules
            .iter()
            .any(|r| r.contains('*') || r.contains("systemd1") || r.contains("noDots")));
    }

    #[test]
    fn an_upper_case_id_owns_no_platform_name() {
        let none = perms(&[]);
        let rules = Policy {
            app_id: "Telephony",
            permissions: &none,
            names: None,
        }
        .session();
        assert!(!rules.contains(&"--own=org.marathonos.Telephony".to_owned()));
        assert!(valid_app_id("shipwright-pacific"));
        assert!(valid_app_id("com.example.app_2"));
        assert!(!valid_app_id("com..example"));
        assert!(!valid_app_id("9lives"));
    }

    struct Stand;

    #[zbus::interface(name = "org.example.Stand")]
    impl Stand {
        /// The pid the bus reports for whoever called.
        async fn caller_pid(
            &self,
            #[zbus(header)] header: zbus::message::Header<'_>,
            #[zbus(connection)] connection: &zbus::Connection,
        ) -> zbus::fdo::Result<u32> {
            let sender = header
                .sender()
                .ok_or_else(|| zbus::fdo::Error::Failed("no sender".into()))?;
            zbus::fdo::DBusProxy::new(connection)
                .await?
                .get_connection_unix_process_id(sender.clone().into())
                .await
        }
    }

    struct Daemon(std::process::Child);

    impl Drop for Daemon {
        fn drop(&mut self) {
            self.0.kill().ok();
            self.0.wait().ok();
        }
    }

    fn found(program: &str) -> bool {
        std::env::var_os("PATH")
            .is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
    }

    /// `busctl` with `args`, inside a bubblewrap sandbox like an app's: its
    /// own pid namespace, and of the test's directory only the proxy's.
    fn sandboxed(root: &Path, proxy: &Path, socket: &str, args: &[&str]) -> (bool, String) {
        let out = Command::new("bwrap")
            .args(["--unshare-pid", "--die-with-parent", "--ro-bind", "/", "/"])
            .args(["--proc", "/proc", "--dev", "/dev", "--tmpfs"])
            .arg(root)
            .arg("--ro-bind")
            .args([proxy, proxy])
            .arg("busctl")
            .arg(format!(
                "--address=unix:path={}",
                proxy.join(socket).display()
            ))
            .args(args)
            .output()
            .unwrap();
        let text = format!(
            "{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        (out.status.success(), text)
    }

    /// A bus of the test's own, with stand-ins for the shell, systemd's
    /// user manager and the shell's NGF (on the system bus, here the same).
    fn private_bus(dir: &Path) -> (Daemon, String, Vec<zbus::Connection>) {
        fs::create_dir(dir).unwrap();
        let address = format!("unix:path={}", dir.join("socket").display());
        let daemon = Daemon(
            Command::new("dbus-daemon")
                .args(["--session", "--nofork", "--nopidfile"])
                .arg(format!("--address={address}"))
                .spawn()
                .unwrap(),
        );
        for _ in 0..100 {
            if dir.join("socket").exists() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        let services = async_io::block_on(async {
            let mut connections = Vec::new();
            for name in ["org.marathonos.Shell", "org.freedesktop.systemd1", NGF] {
                connections.push(
                    zbus::connection::Builder::address(address.as_str())
                        .name(name)
                        .serve_at("/", Stand)
                        .build()
                        .await
                        .unwrap(),
                );
            }
            connections
        });
        (daemon, address, services)
    }

    #[test]
    fn a_sandboxed_app_reaches_only_what_its_policy_names() {
        if !["dbus-daemon", "xdg-dbus-proxy", "bwrap", "busctl"]
            .iter()
            .all(|p| found(p))
        {
            return;
        }
        let root = tempfile::tempdir().unwrap();
        let proxy_dir = root.path().join("proxy");
        fs::create_dir(&proxy_dir).unwrap();
        let (_daemon, address, _services) = private_bus(&root.path().join("bus"));

        let none = perms(&[]);
        let policy = Policy {
            app_id: "notes",
            permissions: &none,
            names: None,
        };
        let proxy = spawn(
            policy.app_id,
            &arguments(&policy, &proxy_dir, &address, &address),
        )
        .unwrap();
        let call = |socket, name| {
            sandboxed(
                root.path(),
                &proxy_dir,
                socket,
                &["call", name, "/", "org.example.Stand", "CallerPid"],
            )
        };

        let (ok, out) = call(SESSION_SOCKET, "org.marathonos.Shell");
        assert!(ok, "the shell: {out}");
        assert_eq!(
            out.trim(),
            format!("u {}", proxy.pid),
            "the bus sees the proxy"
        );
        assert_eq!(
            crate::gate::resolve(u32::try_from(proxy.pid).unwrap()).as_deref(),
            Some("notes"),
            "which the shell knows as the app"
        );

        let (ok, out) = call(SESSION_SOCKET, "org.freedesktop.systemd1");
        assert!(!ok, "systemd's manager is out of reach: {out}");
        let (ok, out) = call(SYSTEM_SOCKET, "org.freedesktop.systemd1");
        assert!(!ok, "on the system bus too: {out}");
        let (ok, out) = call(SYSTEM_SOCKET, NGF);
        assert!(ok, "feedback on the system bus: {out}");

        let own = |name: &str| {
            sandboxed(
                root.path(),
                &proxy_dir,
                SESSION_SOCKET,
                &[
                    "call",
                    "org.freedesktop.DBus",
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "RequestName",
                    "su",
                    name,
                    "0",
                ],
            )
        };
        let (ok, out) = own("org.marathonos.notes");
        assert!(ok, "its own Keel actions name: {out}");
        let (ok, out) = own("org.marathonos.AppRunner.notes");
        assert!(ok, "its runner's name: {out}");
        let (ok, out) = own("org.marathonos.Telephony");
        assert!(!ok, "no platform service's name: {out}");
        let (ok, out) = own("org.marathonos.email");
        assert!(!ok, "no other app's name: {out}");

        let pid = u32::try_from(proxy.pid).unwrap();
        drop(proxy);
        let forgotten = (0..100).any(|_| {
            std::thread::sleep(std::time::Duration::from_millis(20));
            crate::gate::resolve(pid).as_deref() != Some("notes")
        });
        assert!(forgotten, "a closed proxy exits and its pid is forgotten");
    }
}
