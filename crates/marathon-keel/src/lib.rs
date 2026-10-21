//! The Keel host contract (Keel's shell/PROTOCOL.md, version 1): the
//! environment a Keel app reads at start and a peer-to-peer D-Bus server
//! with `org.shipwright.keel.Shell1`. keel-shell plays this role on
//! Sailfish; marathon-app-runner and marathon-keel-host play it here.

pub mod sailjail;

use std::collections::HashMap;
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use async_io::Async;
use futures_lite::StreamExt as _;
use marathon_rt::{io, log};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::OwnedValue;

pub type Ambience = HashMap<String, OwnedValue>;

const PATH: &str = "/org/shipwright/keel/Shell";
const INTERFACE: &str = "org.shipwright.keel.Shell1";
const SHELL: &str = "org.marathonos.Shell";
// Keel's forwarded dconf directories (keel/silica/plugin/src/config.rs).
const FORWARDED: [(&str, &str); 2] = [("/desktop/jolla/theme/", "KEEL_AMBIENCE_"), ("/desktop/sailfish/silica/", "KEEL_SILICA_")];

#[derive(Default)]
struct State {
    ambience: Ambience,
    active: bool,
    cover_status: i32,
    content_orientation: i32,
    peers: Vec<zbus::Connection>,
}

type Callback = Arc<dyn Fn() + Send + Sync>;

#[derive(Clone)]
pub struct Host {
    state: Arc<Mutex<State>>,
    socket: Arc<PathBuf>,
    dpi: i32,
    on_activate: Callback,
    on_ambience: Callback,
}

impl Host {
    /// Listens in `runtime_dir` and follows the shell's ambience, read once
    /// first (up to a second) so the environment carries it. `on_activate`
    /// runs when the app asks to come forward; `on_ambience` when the
    /// environment changes.
    pub fn start(runtime_dir: &Path, dpi: i32, on_activate: Callback, on_ambience: Callback) -> std::io::Result<Self> {
        let id = std::fs::read_to_string("/proc/sys/kernel/random/uuid").unwrap_or_default();
        let path = runtime_dir.join(format!("keel-{}", id.trim()));
        let listener = Async::new(UnixListener::bind(&path)?)?;
        let host = Self { state: Arc::default(), socket: Arc::new(path), dpi, on_activate, on_ambience };
        if let Some(ambience) = async_io::block_on(io::timeout(Duration::from_secs(1), read_ambience())).flatten() {
            host.lock().ambience = ambience;
        }
        let accepting = host.clone();
        io::spawn(async move {
            while let Ok((stream, _)) = listener.accept().await {
                let host = accepting.clone();
                io::spawn(async move {
                    let served = async {
                        let stream = stream.into_inner()?;
                        zbus::connection::Builder::async_io_unix_stream(stream)
                            .server(zbus::Guid::generate())?
                            .p2p()
                            .serve_at(PATH, Shell1(host.clone()))?
                            .build()
                            .await
                    };
                    match served.await {
                        Ok(peer) => host.lock().peers.push(peer),
                        Err(e) => log::warn("keel", format_args!("a peer did not connect: {e}")),
                    }
                });
            }
        });
        let following = host.clone();
        io::spawn(async move {
            if let Err(e) = following.follow_ambience().await {
                log::warn("keel", format_args!("cannot follow the ambience: {e}"));
            }
        });
        Ok(host)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub fn address(&self) -> String {
        format!("unix:path={}", self.socket.display())
    }

    /// Removes the socket, as the process ends.
    pub fn close(&self) {
        std::fs::remove_file(&*self.socket).ok();
    }

    /// What a Keel app reads at start: the protocol, the server, the
    /// ambience's forwarded keys.
    pub fn environment(&self) -> Vec<(String, String)> {
        let mut env: Vec<(String, String)> = [
            ("KEEL_SHELL", "1".to_owned()),
            ("KEEL_SHELL_PROTOCOL", "1".to_owned()),
            ("KEEL_SHELL_DBUS", self.address()),
            ("KEEL_SHELL_COVER_TITLE", "keel:cover".to_owned()),
            ("KEEL_SHELL_COVER_ENABLED", "1".to_owned()),
            ("KEEL_SHELL_DPI", self.dpi.to_string()),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_owned(), v))
        .collect();
        let mut keys = Vec::new();
        for (key, value) in &self.lock().ambience {
            for (dir, prefix) in FORWARDED {
                let Some(name) = key.strip_prefix(dir) else { continue };
                let name: String = name.to_uppercase().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
                env.push((format!("{prefix}{name}"), text(value)));
                keys.push(key.clone());
            }
        }
        if !keys.is_empty() {
            keys.sort();
            env.push(("KEEL_AMBIENCE_KEYS".to_owned(), keys.join(":")));
        }
        env
    }

    pub fn set_active(&self, active: bool) {
        self.change(|s| std::mem::replace(&mut s.active, active) != active, "ActiveChanged", active);
    }

    /// 1 while the app's cover is on screen in the task switcher.
    pub fn set_cover_status(&self, status: i32) {
        self.change(|s| std::mem::replace(&mut s.cover_status, status) != status, "CoverStatusChanged", status);
    }

    pub fn request_close(&self) {
        self.emit("CloseRequested", ());
    }

    fn change<T: Body + zbus::zvariant::Type>(&self, apply: impl FnOnce(&mut State) -> bool, member: &'static str, value: T) {
        if apply(&mut self.lock()) {
            self.emit(member, (value,));
        }
    }

    fn emit<B: Body>(&self, member: &'static str, body: B) {
        let peers = self.lock().peers.clone();
        io::spawn(async move {
            for peer in peers {
                peer.emit_signal(None::<&str>, PATH, INTERFACE, member, &body).await.ok();
            }
        });
    }

    /// The shell's changes, and a read whenever the shell (re)appears.
    async fn follow_ambience(&self) -> zbus::Result<()> {
        let bus = io::session_bus().await?;
        let rule = zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender(SHELL)?
            .interface("org.marathonos.Shell.Ambience1")?
            .member("AmbienceChanged")?
            .build();
        let mut changes = zbus::MessageStream::for_match_rule(rule, &bus, None).await?;
        let mut owners = zbus::fdo::DBusProxy::new(&bus).await?.receive_name_owner_changed_with_args(&[(0, SHELL)]).await?;
        let reread = self.clone();
        io::spawn(async move {
            while let Some(change) = owners.next().await {
                if change.args().is_ok_and(|a| a.new_owner().is_some()) {
                    if let Some(ambience) = read_ambience().await {
                        reread.set_ambience(ambience);
                    }
                }
            }
        });
        while let Some(Ok(message)) = changes.next().await {
            if let Ok((ambience,)) = message.body().deserialize::<(Ambience,)>() {
                self.set_ambience(ambience);
            }
        }
        Ok(())
    }

    fn set_ambience(&self, ambience: Ambience) {
        let changed = {
            let mut s = self.lock();
            let changed = s.ambience != ambience;
            s.ambience.clone_from(&ambience);
            changed
        };
        if changed {
            self.emit("AmbienceChanged", (ambience,));
            (self.on_ambience)();
        }
    }
}

/// A signal's arguments.
trait Body: serde::Serialize + zbus::zvariant::DynamicType + Send + Sync + 'static {}
impl<T: serde::Serialize + zbus::zvariant::DynamicType + Send + Sync + 'static> Body for T {}

async fn read_ambience() -> Option<Ambience> {
    let bus = io::session_bus().await.ok()?;
    let reply = bus.call_method(Some(SHELL), "/org/marathonos/Shell/Ambience", Some("org.marathonos.Shell.Ambience1"), "GetAmbience", &()).await.ok()?;
    reply.body().deserialize().ok()
}

/// As `QVariant::toString` gives it.
fn text(value: &OwnedValue) -> String {
    use zbus::zvariant::Value;
    match &**value {
        Value::Str(s) => s.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::I32(n) => n.to_string(),
        Value::U32(n) => n.to_string(),
        Value::I64(n) => n.to_string(),
        Value::U64(n) => n.to_string(),
        Value::F64(n) => n.to_string(),
        Value::U8(n) => n.to_string(),
        Value::I16(n) => n.to_string(),
        Value::U16(n) => n.to_string(),
        _ => String::new(),
    }
}

struct Shell1(Host);

#[allow(clippy::unused_self, reason = "D-Bus methods and properties")]
#[zbus::interface(name = "org.shipwright.keel.Shell1")]
impl Shell1 {
    fn ping(&self) -> &'static str {
        "marathon"
    }

    fn get_ambience(&self) -> Ambience {
        self.0.lock().ambience.clone()
    }

    fn activate(&self) {
        (self.0.on_activate)();
    }

    async fn set_content_orientation(&self, degrees: i32, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        let changed = std::mem::replace(&mut self.0.lock().content_orientation, degrees) != degrees;
        if changed {
            emitter.emit(INTERFACE, "ContentOrientationChanged", &(degrees,)).await.ok();
        }
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        1
    }

    #[zbus(property)]
    fn orientation(&self) -> i32 {
        0
    }

    #[zbus(property)]
    fn content_orientation(&self) -> i32 {
        self.0.lock().content_orientation
    }

    #[zbus(property)]
    fn active(&self) -> bool {
        self.0.lock().active
    }

    #[zbus(property)]
    fn cover_status(&self) -> i32 {
        self.0.lock().cover_status
    }

    #[zbus(property)]
    fn ambience(&self) -> Ambience {
        self.0.lock().ambience.clone()
    }

    #[zbus(property)]
    fn dpi(&self) -> i32 {
        self.0.dpi
    }
}

/// The bus name the shell calls an app's runner by.
pub fn runner_name(app_id: &str) -> String {
    let id: String = app_id.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' }).collect();
    format!("org.marathonos.AppRunner.{id}")
}

pub const RUNNER_PATH: &str = "/org/marathonos/AppRunner/Lifecycle";

/// The caller is the shell that started this process (`MARATHON_SHELL_PID`).
pub async fn caller_is_shell(header: &Header<'_>) -> zbus::fdo::Result<()> {
    let denied = |why: &str| zbus::fdo::Error::AccessDenied(why.to_owned());
    let shell: u32 = std::env::var("MARATHON_SHELL_PID").ok().and_then(|p| p.trim().parse().ok()).ok_or_else(|| denied("MARATHON_SHELL_PID not set"))?;
    let sender = header.sender().ok_or_else(|| denied("Unable to resolve sender PID"))?;
    let bus = io::session_bus().await?;
    let pid = zbus::fdo::DBusProxy::new(&bus).await?.get_connection_unix_process_id(sender.clone().into()).await.map_err(|e| denied(&format!("Unable to resolve sender PID: {e}")))?;
    if pid == shell {
        Ok(())
    } else {
        Err(denied("Caller is not the shell"))
    }
}

/// Asks the shell to bring `app_id` forward.
pub fn launch(app_id: String) {
    io::spawn(async move {
        let Ok(bus) = io::session_bus().await else { return };
        bus.call_method(Some(SHELL), "/org/marathonos/Shell/Navigation", Some("org.marathonos.Shell.Navigation1"), "LaunchApp", &(app_id,)).await.ok();
    });
}
