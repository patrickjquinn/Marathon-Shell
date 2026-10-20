//! `Updates`: over-the-air updates of the OS image through systemd-sysupdated
//! (`org.freedesktop.sysupdate1`), for Settings and the "Software update"
//! notifications. Downloads wait for an unmetered network and a charged
//! battery; a booted image older than one installed here is a rollback.
//! With automatic updates (on by default) an update downloads once allowed,
//! and an installed one restarts between 02:00 and 05:00 while the device is
//! idle on charge; "Tonight" asks for that restart without them.
//!
//! The state machine is `Machine`; one actor on the I/O thread drives it,
//! sysupdated and the notifications, and hands Qt a view of it.

use std::collections::HashMap;
use std::path::Path;
use std::pin::Pin;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant};
use futures_lite::{future, StreamExt};
use quick_xml::events::Event;
use serde::{Deserialize, Serialize};
use zbus::fdo::{self, PropertiesProxy};
use zbus::message::Header;
use zbus::names::InterfaceName;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

use crate::notifications::NotificationsProxy;
use crate::ipc::{self, value};
use crate::{clock, io, log, stored, variant};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        type Updates = super::UpdatesRust;

        /// Settings' view: state, osVersion, availableVersion, downloadSize,
        /// releaseNotes, currentReleaseNotes, progress, blockedReason,
        /// rolledBackVersion, lastError, lastCheckedMs, autoUpdate and
        /// restartScheduled.
        #[qinvokable]
        fn state(self: &Updates) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "checkNow"]
        fn check_now(self: &Updates);
        #[qinvokable]
        fn install(self: &Updates);
        #[qinvokable]
        fn cancel(self: &Updates);
        #[qinvokable]
        fn reboot(self: &Updates);
        /// "Tonight": restart overnight into the installed update.
        #[qinvokable]
        #[cxx_name = "scheduleRestart"]
        fn schedule_restart(self: &Updates);
        #[qinvokable]
        #[cxx_name = "setAutoUpdate"]
        fn set_auto_update(self: &Updates, on: bool);
        /// The phone asks for a PIN at startup: a restart nobody watches
        /// would wait at the prompt, alarms and calls with it.
        #[qinvokable]
        #[cxx_name = "setStartupPin"]
        fn set_startup_pin(self: &Updates, on: bool);
        /// What a download or the overnight restart waits for may have
        /// changed. `idle`: the screen is off and no call or alarm rings.
        #[qinvokable]
        fn reconsider(self: &Updates, idle: bool);

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "rebootRequested"]
        fn reboot_requested(self: Pin<&mut Self>);
        /// When the next overnight restart window opens, in seconds since
        /// the epoch; 0 when none is due.
        #[qsignal]
        #[cxx_name = "restartWindowChanged"]
        fn restart_window_changed(self: Pin<&mut Self>, at: i64);
        /// A notification asks for Settings → Software updates.
        #[qsignal]
        #[cxx_name = "settingsRequested"]
        fn settings_requested(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Updates {}
    impl cxx_qt::Initialize for Updates {}
}

use qobject::Updates;

type Qt = CxxQtThread<Updates>;

const FIRST_CHECK: Duration = Duration::from_secs(30);
const CHECK_EVERY: Duration = Duration::from_hours(6);
const RESTART_HOURS: std::ops::Range<i32> = 2..5;

#[derive(Default)]
pub struct UpdatesRust {
    view: QMap<QMapPair_QString_QVariant>,
    json: serde_json::Value,
    actor: Option<Sender<Msg>>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum State {
    #[default]
    Probing,
    Unsupported,
    Idle,
    Checking,
    UpToDate,
    Available,
    Downloading,
    ReadyToReboot,
    RolledBack,
    Error,
}

impl State {
    /// As Settings names it: "readyToReboot".
    fn name(self) -> String {
        let name = format!("{self:?}");
        name[..1].to_lowercase() + &name[1..]
    }
}

/// News, once per version of each kind. Restart: installed and waiting for a
/// restart. Updated: this boot is the first into the version.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Notice {
    Available,
    Restart,
    RolledBack,
    Updated,
}

/// What the system says about downloading and restarting right now.
#[derive(Clone, Copy, Debug, Default)]
struct Conditions {
    /// `NetworkManager`'s `NMMetered`: 1 yes, 3 guess-yes.
    metered: u32,
    /// `UPower`'s display device: percent and state, when it has a battery.
    battery: Option<(f64, u32)>,
    idle: bool,
}

impl Conditions {
    /// Charging, fully charged or pending charge.
    fn on_charge(&self) -> bool {
        self.battery.is_none_or(|(_, state)| matches!(state, 1 | 4 | 5))
    }

    /// "metered", "battery" or "" when a download may start.
    fn block_reason(&self) -> &'static str {
        if matches!(self.metered, 1 | 3) {
            "metered"
        } else if !self.on_charge() && self.battery.is_some_and(|(percent, _)| percent < 30.0) {
            "battery"
        } else {
            ""
        }
    }
}

#[derive(Debug, PartialEq)]
enum Effect {
    Check,
    Info(String),
    Install,
    Cancel,
    Reboot,
    Notice(Notice, String),
}

/// What outlives the shell, in updates.json.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct Saved {
    /// Automatic updates are off.
    manual: bool,
    installed_version: String,
    installed_boot_id: String,
    last_checked: i64,
    last_seen_version: String,
    tonight_version: String,
    notices: HashMap<String, String>,
    notice_id: u32,
}

impl Saved {
    fn load() -> Self {
        stored::load("updates.json").unwrap_or_else(|| Self::from_qsettings(&marathon_rt::dirs::config().join("Marathon OS/Marathon Shell.conf")))
    }

    /// The `[updates]` group the C++ shell kept in its `QSettings`.
    fn from_qsettings(path: &Path) -> Self {
        let mut saved = Self::default();
        for (key, value) in stored::qsettings(path, "updates") {
            match key.as_str() {
                "autoUpdate" => saved.manual = value == "false",
                "installedVersion" => saved.installed_version = value,
                "installedBootId" => saved.installed_boot_id = value,
                "lastChecked" => saved.last_checked = value.parse().unwrap_or_default(),
                "lastSeenVersion" => saved.last_seen_version = value,
                "tonightVersion" => saved.tonight_version = value,
                "noticeId" => saved.notice_id = value.parse().unwrap_or_default(),
                key => {
                    if let Some(kind) = key.strip_prefix("notice\\") {
                        saved.notices.insert(kind.to_owned(), value);
                    }
                }
            }
        }
        saved
    }
}

#[derive(Default)]
struct Machine {
    os_version: String,
    boot_id: String,
    saved: Saved,
    dirty: bool,
    conditions: Conditions,
    state: State,
    available: String,
    download_size: i64,
    notes: String,
    current_notes: String,
    progress: i32,
    /// While Downloading: the download is in and `progress` is the install's.
    installing: bool,
    blocked: &'static str,
    rolled_back: String,
    error: String,
    startup_pin: bool,
    cancelled: String,
    effects: Vec<Effect>,
}

impl Machine {
    fn new(os_version: String, boot_id: String, saved: Saved) -> Self {
        Self { os_version, boot_id, saved, download_size: -1, ..Self::default() }
    }

    /// What Settings shows.
    fn view(&self) -> serde_json::Value {
        serde_json::json!({
            "state": self.state.name(),
            "osVersion": self.os_version,
            "availableVersion": self.available,
            "downloadSize": self.download_size,
            "releaseNotes": self.notes,
            "currentReleaseNotes": self.current_notes,
            "progress": self.progress,
            "blockedReason": self.blocked,
            "rolledBackVersion": self.rolled_back,
            "lastError": self.error,
            "lastCheckedMs": self.saved.last_checked,
            "autoUpdate": !self.saved.manual,
            "restartScheduled": self.restart_scheduled(),
        })
    }

    /// Whether the host has an update target, and the newest version on
    /// disk: not the booted one while an update waits for a restart, or
    /// after a rollback. True when the auto-check should start.
    fn probed(&mut self, supported: bool, installed: &str) -> bool {
        if !supported || self.os_version.is_empty() {
            self.state = State::Unsupported;
            return false;
        }
        let ours = self.saved.installed_version.clone();
        // Before lastSeenVersion was kept, only an install of ours says
        // this version is new.
        let seen = &self.saved.last_seen_version;
        let updated = if seen.is_empty() { ours == self.os_version } else { *seen != self.os_version };
        self.saved.last_seen_version.clone_from(&self.os_version);
        self.dirty = true;
        if !installed.is_empty() && installed != self.os_version {
            // Installed in an earlier boot and not running: it failed its
            // health check and systemd-boot fell back to this one.
            if ours == installed && self.saved.installed_boot_id != self.boot_id {
                installed.clone_into(&mut self.rolled_back);
                self.state = State::RolledBack;
                self.announce(Notice::RolledBack, installed);
            } else {
                installed.clone_into(&mut self.available);
                self.state = State::ReadyToReboot;
                self.announce(Notice::Restart, installed);
                return false;
            }
        } else {
            self.state = State::Idle;
            if updated {
                let os = self.os_version.clone();
                self.announce(Notice::Updated, &os);
                self.effects.push(Effect::Info(os));
            }
        }
        true
    }

    fn announce(&mut self, kind: Notice, version: &str) {
        let key = format!("{kind:?}");
        if self.saved.notices.get(&key).is_some_and(|v| v == version) {
            return;
        }
        self.saved.notices.insert(key, version.to_owned());
        self.dirty = true;
        self.effects.push(Effect::Notice(kind, version.to_owned()));
    }

    fn mark_checked(&mut self) {
        self.saved.last_checked = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(0));
        self.dirty = true;
    }

    fn check_now(&mut self) {
        if !matches!(self.state, State::Idle | State::UpToDate | State::Available | State::RolledBack | State::Error) {
            return;
        }
        self.error.clear();
        self.blocked = "";
        self.state = State::Checking;
        self.effects.push(Effect::Check);
    }

    /// The newer version on the server, or "".
    fn checked(&mut self, version: &str) {
        if self.state != State::Checking {
            return;
        }
        self.mark_checked();
        if self.current_notes.is_empty() {
            self.effects.push(Effect::Info(self.os_version.clone()));
        }
        if version.is_empty() {
            self.available.clear();
            self.state = if self.rolled_back.is_empty() { State::UpToDate } else { State::RolledBack };
            return;
        }
        if version != self.available {
            version.clone_into(&mut self.available);
            self.download_size = -1;
            self.notes.clear();
        }
        self.state = State::Available;
        self.effects.push(Effect::Info(version.to_owned()));
        if !self.auto_install() {
            self.announce(Notice::Available, version);
        }
    }

    fn release_info(&mut self, version: &str, download_size: i64, notes: String) {
        if version == self.os_version && !notes.is_empty() {
            self.current_notes.clone_from(&notes);
        }
        if version == self.available {
            self.download_size = download_size;
            self.notes = notes;
        }
    }

    fn install(&mut self) {
        if self.state != State::Available {
            return;
        }
        self.blocked = self.conditions.block_reason();
        if !self.blocked.is_empty() {
            return;
        }
        self.error.clear();
        self.progress = 0;
        self.installing = false;
        self.state = State::Downloading;
        self.effects.push(Effect::Install);
    }

    fn cancel(&mut self) {
        if self.state != State::Downloading {
            return;
        }
        self.effects.push(Effect::Cancel);
        self.cancelled.clone_from(&self.available);
        self.progress = 0;
        self.state = State::Available;
    }

    fn progressed(&mut self, percent: i32) {
        if self.state == State::Downloading {
            self.progress = percent;
        }
    }

    /// The download is in; the install starts.
    fn installing(&mut self) {
        if self.state == State::Downloading {
            self.installing = true;
            self.progress = 0;
        }
    }

    fn installed(&mut self, version: &str) {
        if self.state != State::Downloading {
            return;
        }
        version.clone_into(&mut self.saved.installed_version);
        self.saved.installed_boot_id.clone_from(&self.boot_id);
        self.dirty = true;
        version.clone_into(&mut self.available);
        self.progress = 100;
        self.state = State::ReadyToReboot;
        self.announce(Notice::Restart, version);
    }

    fn failed(&mut self, error: String) {
        if !matches!(self.state, State::Checking | State::Downloading) {
            return;
        }
        log::warn("updates", format_args!("{} failed: {error}", self.state.name()));
        if self.state == State::Checking {
            self.mark_checked();
        }
        self.error = error;
        self.state = State::Error;
    }

    fn reboot(&mut self) {
        if self.state == State::ReadyToReboot {
            self.effects.push(Effect::Reboot);
        }
    }

    fn set_auto_update(&mut self, on: bool) {
        if on == self.saved.manual {
            self.saved.manual = !on;
            self.dirty = true;
            self.auto_install();
        }
    }

    fn auto_install(&mut self) -> bool {
        if self.saved.manual || self.state != State::Available || self.available == self.cancelled {
            return false;
        }
        self.install();
        self.state == State::Downloading
    }

    fn schedule_restart(&mut self) {
        if self.state == State::ReadyToReboot {
            self.saved.tonight_version.clone_from(&self.available);
            self.dirty = true;
        }
    }

    fn restart_scheduled(&self) -> bool {
        self.state == State::ReadyToReboot && !self.startup_pin && (!self.saved.manual || self.saved.tonight_version == self.available)
    }

    /// At `hour`, whether to restart into the installed update now.
    fn restart_now(&self, hour: i32) -> bool {
        self.restart_scheduled() && RESTART_HOURS.contains(&hour) && self.conditions.idle && self.conditions.on_charge()
    }
}

enum Msg {
    CheckNow,
    Install,
    Cancel,
    Reboot,
    ScheduleRestart,
    AutoUpdate(bool),
    StartupPin(bool),
    Reconsider(bool),
    Probed(Option<OwnedObjectPath>, String),
    Checked(Result<String, String>),
    Info(String, i64, String),
    Job(OwnedObjectPath),
    Progress(i32),
    Installing,
    Installed(Result<String, String>),
    AutoCheck,
    Window,
    Action(u32, String),
}

impl Msg {
    fn needs_conditions(&self) -> bool {
        !matches!(self, Msg::Progress(_) | Msg::Job(_) | Msg::Info(..) | Msg::Probed(..))
    }
}

impl cxx_qt::Initialize for Updates {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::unbounded();
        io::spawn(run(self.qt_thread(), tx.clone(), rx));
        self.as_mut().rust_mut().actor = Some(tx);
        self.as_mut().on_state_changed(|obj| ipc::signal("Updates", "StateChanged", (wire(&obj.json),))).release();
        ipc::export("Updates", Updates1 { qt: self.qt_thread() });
    }
}

impl Updates {
    fn send(&self, msg: Msg) {
        if let Some(actor) = &self.actor {
            actor.try_send(msg).ok();
        }
    }

    fn state(&self) -> QMap<QMapPair_QString_QVariant> {
        self.view.clone()
    }

    fn check_now(&self) {
        self.send(Msg::CheckNow);
    }

    fn install(&self) {
        self.send(Msg::Install);
    }

    fn cancel(&self) {
        self.send(Msg::Cancel);
    }

    fn reboot(&self) {
        self.send(Msg::Reboot);
    }

    fn schedule_restart(&self) {
        self.send(Msg::ScheduleRestart);
    }

    fn set_auto_update(&self, on: bool) {
        self.send(Msg::AutoUpdate(on));
    }

    fn set_startup_pin(&self, on: bool) {
        self.send(Msg::StartupPin(on));
    }

    fn reconsider(&self, idle: bool) {
        self.send(Msg::Reconsider(idle));
    }
}

fn after(tx: &Sender<Msg>, wait: Duration, msg: Msg) {
    let tx = tx.clone();
    io::spawn(async move {
        Timer::after(wait).await;
        tx.send(msg).await.ok();
    });
}

struct Actor {
    qt: Qt,
    tx: Sender<Msg>,
    m: Machine,
    notifier: Notifier,
    target: Option<OwnedObjectPath>,
    job: Option<OwnedObjectPath>,
    shown: serde_json::Value,
    window: i64,
}

async fn run(qt: Qt, tx: Sender<Msg>, rx: Receiver<Msg>) {
    let os_release = ["/etc/os-release", "/usr/lib/os-release"].into_iter().find(|p| Path::new(p).exists()).unwrap_or_default();
    let boot_id = io::read::<String>("/proc/sys/kernel/random/boot_id").unwrap_or_default();
    let m = Machine::new(image_version(Path::new(os_release)), boot_id, Saved::load());
    let notifier = Notifier { id: m.saved.notice_id, shown: None };
    spawn(&tx, probe());
    Notifier::listen(&tx);
    let mut actor = Actor { qt, tx, m, notifier, target: None, job: None, shown: serde_json::Value::Null, window: 0 };
    while let Ok(msg) = rx.recv().await {
        if msg.needs_conditions() {
            actor.m.conditions = conditions(actor.m.conditions.idle).await;
        }
        actor.handle(msg);
        let notices = actor.execute();
        actor.publish(notices).await;
    }
}

impl Actor {
    fn handle(&mut self, msg: Msg) {
        let m = &mut self.m;
        match msg {
            Msg::CheckNow | Msg::AutoCheck => m.check_now(),
            Msg::Install => m.install(),
            Msg::Cancel => m.cancel(),
            Msg::Reboot => m.reboot(),
            Msg::ScheduleRestart => m.schedule_restart(),
            Msg::AutoUpdate(on) => m.set_auto_update(on),
            Msg::StartupPin(on) => m.startup_pin = on,
            Msg::Reconsider(idle) => {
                m.conditions.idle = idle;
                m.auto_install();
            }
            Msg::Probed(path, installed) => {
                if m.probed(path.is_some(), &installed) {
                    after(&self.tx, FIRST_CHECK, Msg::AutoCheck);
                    let tx = self.tx.clone();
                    io::spawn(async move {
                        loop {
                            Timer::after(CHECK_EVERY).await;
                            if tx.send(Msg::AutoCheck).await.is_err() {
                                break;
                            }
                        }
                    });
                }
                self.target = path;
            }
            Msg::Checked(Ok(version)) => m.checked(&version),
            Msg::Checked(Err(e)) | Msg::Installed(Err(e)) => m.failed(e),
            Msg::Info(version, size, notes) => m.release_info(&version, size, notes),
            Msg::Job(path) => self.job = Some(path),
            Msg::Progress(percent) => m.progressed(percent),
            Msg::Installing => m.installing(),
            Msg::Installed(Ok(version)) => m.installed(&version),
            Msg::Window => {}
            Msg::Action(id, action) => match self.notifier.action(id, &action) {
                Some(Action::Settings) => queue(&self.qt, Updates::settings_requested),
                Some(Action::Download) => {
                    m.install();
                    // A gate held it back; Settings says which.
                    if m.state != State::Downloading {
                        queue(&self.qt, Updates::settings_requested);
                    }
                }
                Some(Action::Restart) => m.reboot(),
                Some(Action::Tonight) => m.schedule_restart(),
                None => {}
            },
        }
    }

    /// Starts what the machine asked for; the notices are for after the
    /// progress row is gone.
    fn execute(&mut self) -> Vec<(Notice, String)> {
        let mut notices = Vec::new();
        for effect in self.m.effects.drain(..) {
            let target = self.target.clone().unwrap_or_default();
            match effect {
                Effect::Check => spawn(&self.tx, async move {
                    let found = async { sysupdate(&target).await?.check_new().await.map_err(text) };
                    Ok(Msg::Checked(found.await))
                }),
                Effect::Info(version) => spawn(&self.tx, async move {
                    let (size, notes) = release_info(&target, &version).await;
                    Ok(Msg::Info(version, size, notes))
                }),
                Effect::Install => {
                    let actor = self.tx.clone();
                    spawn(&self.tx, async move { Ok(Msg::Installed(install(&actor, &target).await)) });
                }
                Effect::Cancel => {
                    if let Some(path) = self.job.take() {
                        io::spawn(async move {
                            if let Err(e) = cancel(path).await {
                                log::warn("updates", format_args!("cancel: {e}"));
                            }
                        });
                    }
                }
                Effect::Reboot => queue(&self.qt, Updates::reboot_requested),
                Effect::Notice(kind, version) => notices.push((kind, version)),
            }
        }
        notices
    }

    async fn publish(&mut self, notices: Vec<(Notice, String)>) {
        let m = &mut self.m;
        let view = m.view();
        if view != self.shown {
            self.notifier.show_progress(m).await;
            self.shown = view.clone();
            self.qt
                .queue(move |mut obj| {
                    let mut rust = obj.as_mut().rust_mut();
                    rust.view = variant::map(&view);
                    rust.json = view;
                    obj.state_changed();
                })
                .ok();
        }
        for (kind, version) in notices {
            self.notifier.post(m, kind, &version).await;
        }
        if m.saved.notice_id != self.notifier.id {
            m.saved.notice_id = self.notifier.id;
            m.dirty = true;
        }
        if std::mem::take(&mut m.dirty) {
            stored::save("updates.json", &m.saved);
        }

        let now = clock::now();
        if m.restart_now(clock::local(now).map_or(0, |tm| tm.tm_hour)) {
            log::warn("updates", format_args!("restarting overnight into {}", m.available));
            queue(&self.qt, Updates::reboot_requested);
        }
        let next = if m.restart_scheduled() { clock::next(now, RESTART_HOURS.start) } else { 0 };
        if next != self.window {
            self.window = next;
            if next > now {
                after(&self.tx, Duration::from_secs(u64::try_from(next - now).unwrap_or_default()), Msg::Window);
            }
            self.qt.queue(move |obj| obj.restart_window_changed(next)).ok();
        }
    }
}

fn queue(qt: &Qt, signal: impl FnOnce(Pin<&mut Updates>) + Send + 'static) {
    qt.queue(signal).ok();
}

/// Runs `task` and hands the actor its answer; a task that cannot reach the
/// bus answers nothing.
fn spawn(tx: &Sender<Msg>, task: impl future::Future<Output = Result<Msg, String>> + Send + 'static) {
    let tx = tx.clone();
    io::spawn(async move {
        match task.await {
            Ok(msg) => {
                tx.send(msg).await.ok();
            }
            Err(e) => log::warn("updates", e),
        }
    });
}

fn text(e: zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(_, Some(message), _) => message,
        e => e.to_string(),
    }
}

#[zbus::proxy(
    interface = "org.freedesktop.sysupdate1.Manager",
    default_service = "org.freedesktop.sysupdate1",
    default_path = "/org/freedesktop/sysupdate1"
)]
trait Manager {
    fn list_targets(&self) -> zbus::Result<Vec<(String, String, OwnedObjectPath)>>;
    #[zbus(signal)]
    fn job_removed(&self, id: u64, path: OwnedObjectPath, status: i32) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.freedesktop.sysupdate1.Target", default_service = "org.freedesktop.sysupdate1")]
trait Target {
    fn get_version(&self) -> zbus::Result<String>;
    fn get_app_stream(&self) -> zbus::Result<Vec<String>>;
    #[zbus(allow_interactive_auth)]
    fn check_new(&self) -> zbus::Result<String>;
    // An empty version stays under polkit's update action; a named one is
    // update-to-version, which asks for a password.
    #[zbus(allow_interactive_auth)]
    fn acquire(&self, version: &str, flags: u64) -> zbus::Result<(String, u64, OwnedObjectPath)>;
    #[zbus(allow_interactive_auth)]
    fn install(&self, version: &str, flags: u64) -> zbus::Result<(String, u64, OwnedObjectPath)>;
}

#[zbus::proxy(interface = "org.freedesktop.sysupdate1.Job", default_service = "org.freedesktop.sysupdate1")]
trait Job {
    #[zbus(allow_interactive_auth)]
    fn cancel(&self) -> zbus::Result<()>;
    #[zbus(property)]
    fn progress(&self) -> zbus::Result<u32>;
}

async fn sysupdate(target: &OwnedObjectPath) -> Result<TargetProxy<'static>, String> {
    let bus = io::system_bus().await.map_err(text)?;
    TargetProxy::builder(&bus).path(target.clone()).map_err(text)?.build().await.map_err(text)
}

async fn probe() -> Result<Msg, String> {
    let bus = io::system_bus().await.map_err(text)?;
    let targets = match ManagerProxy::new(&bus).await.map_err(text)?.list_targets().await {
        Ok(targets) => targets,
        Err(e) => {
            log::warn("updates", format_args!("no update service: {}", text(e)));
            return Ok(Msg::Probed(None, String::new()));
        }
    };
    let Some((_, _, path)) = targets.into_iter().find(|(class, _, _)| class == "host") else {
        return Ok(Msg::Probed(None, String::new()));
    };
    let installed = sysupdate(&path).await?.get_version().await.unwrap_or_else(|e| {
        log::warn("updates", format_args!("GetVersion: {}", text(e)));
        String::new()
    });
    Ok(Msg::Probed(Some(path), installed))
}

/// Acquire downloads the newest version into the free slots; Install then
/// makes it the one booted next.
async fn install(tx: &Sender<Msg>, target: &OwnedObjectPath) -> Result<String, String> {
    job(tx, target, false).await?;
    tx.send(Msg::Installing).await.ok();
    job(tx, target, true).await
}

async fn job(tx: &Sender<Msg>, target: &OwnedObjectPath, install: bool) -> Result<String, String> {
    let bus = io::system_bus().await.map_err(text)?;
    let mut removed = ManagerProxy::new(&bus).await.map_err(text)?.receive_job_removed().await.map_err(text)?;
    let target = sysupdate(target).await?;
    let (version, id, path) = if install { target.install("", 0).await } else { target.acquire("", 0).await }.map_err(text)?;
    tx.send(Msg::Job(path.clone())).await.ok();
    let job = JobProxy::builder(&bus).path(path).map_err(text)?.build().await.map_err(text)?;
    let mut progress = job.receive_progress_changed().await;
    loop {
        let next = future::or(async { Err(progress.next().await) }, async { Ok(removed.next().await) }).await;
        match next {
            Err(Some(changed)) => {
                if let Ok(percent) = changed.get().await {
                    tx.send(Msg::Progress(i32::try_from(percent).unwrap_or(100))).await.ok();
                }
            }
            Ok(Some(signal)) => {
                let Ok(args) = signal.args() else { continue };
                if args.id != id {
                    continue;
                }
                return match args.status {
                    0 => Ok(version),
                    status if status > 0 => Err(format!("systemd-sysupdate exited with status {status}")),
                    status => Err(std::io::Error::from_raw_os_error(-status).to_string()),
                };
            }
            Err(None) | Ok(None) => return Err("The update service went away".to_owned()),
        }
    }
}

async fn cancel(path: OwnedObjectPath) -> zbus::Result<()> {
    JobProxy::builder(&io::system_bus().await?).path(path)?.build().await?.cancel().await
}

/// Download size (-1 unknown) and notes for a version, from the target's
/// `AppStream` catalog, which the publisher writes next to `SHA256SUMS`.
async fn release_info(target: &OwnedObjectPath, version: &str) -> (i64, String) {
    let urls = match sysupdate(target).await {
        Ok(target) => target.get_app_stream().await.map_err(text),
        Err(e) => Err(e),
    };
    let Some(url) = urls.unwrap_or_else(|e| {
        log::warn("updates", format_args!("GetAppStream: {e}"));
        Vec::new()
    }).into_iter().next() else {
        return (-1, String::new());
    };
    let fetched = blocking::unblock(move || {
        let agent: ureq::Agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(30))).build().into();
        agent.get(&url).call()?.body_mut().read_to_vec()
    })
    .await;
    match fetched {
        Ok(xml) => app_stream(&xml, version).unwrap_or((-1, String::new())),
        Err(e) => {
            log::warn("updates", format_args!("AppStream: {e}"));
            (-1, String::new())
        }
    }
}

/// The release's download sizes, summed, and its notes: paragraphs and
/// bulleted list items, a line each.
fn app_stream(xml: &[u8], version: &str) -> Option<(i64, String)> {
    let mut reader = quick_xml::Reader::from_reader(xml);
    let mut buf = Vec::new();
    let (mut size, mut notes, mut text) = (-1_i64, Vec::new(), String::new());
    let (mut in_release, mut download) = (false, false);
    loop {
        match reader.read_event_into(&mut buf).ok()? {
            Event::Start(e) => {
                let attribute = |name| e.try_get_attribute(name).ok().flatten().map(|a| a.value.into_owned());
                match e.name().as_ref() {
                    "release" => in_release = attribute("version").as_deref() == Some(version),
                    "size" => download = attribute("type").as_deref() == Some("download"),
                    _ => {}
                }
                text.clear();
            }
            Event::Text(t) => text.push_str(&t),
            Event::GeneralRef(r) => match r.resolve_char_ref() {
                Ok(Some(c)) => text.push(c),
                _ => text.push_str(quick_xml::escape::resolve_predefined_entity(&r).unwrap_or_default()),
            },
            Event::End(e) => {
                let line = text.split_whitespace().collect::<Vec<_>>().join(" ");
                match e.name().as_ref() {
                    "release" => in_release = false,
                    "size" if in_release && download => {
                        if let Ok(bytes) = line.parse::<i64>() {
                            size = size.max(0) + bytes;
                        }
                    }
                    "p" if in_release => notes.push(line),
                    "li" if in_release => notes.push(format!("• {line}")),
                    _ => {}
                }
                text.clear();
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    Some((size, notes.join("\n")))
}

/// `IMAGE_VERSION` from an os-release file.
fn image_version(os_release: &Path) -> String {
    let text = std::fs::read_to_string(os_release).unwrap_or_default();
    let value = text.lines().find_map(|l| l.trim().strip_prefix("IMAGE_VERSION=")).unwrap_or_default();
    match value.as_bytes() {
        [q @ (b'"' | b'\''), .., last] if last == q && value.len() >= 2 => value[1..value.len() - 1].to_owned(),
        _ => value.to_owned(),
    }
}

async fn property(bus: &zbus::Connection, service: &'static str, path: &'static str, interface: &'static str, name: &str) -> Option<OwnedValue> {
    let props = PropertiesProxy::builder(bus).destination(service).ok()?.path(path).ok()?.build().await.ok()?;
    props.get(InterfaceName::from_static_str_unchecked(interface), name).await.ok()
}

async fn conditions(idle: bool) -> Conditions {
    let Ok(bus) = io::system_bus().await else { return Conditions { idle, ..Conditions::default() } };
    let nm = "org.freedesktop.NetworkManager";
    let metered = property(&bus, nm, "/org/freedesktop/NetworkManager", nm, "Metered").await.and_then(|v| u32::try_from(v).ok()).unwrap_or(0);
    let (upower, device, iface) = ("org.freedesktop.UPower", "/org/freedesktop/UPower/devices/DisplayDevice", "org.freedesktop.UPower.Device");
    let present = property(&bus, upower, device, iface, "IsPresent").await.and_then(|v| bool::try_from(v).ok()).unwrap_or(false);
    let battery = if present {
        let percent = property(&bus, upower, device, iface, "Percentage").await.and_then(|v| f64::try_from(v).ok()).unwrap_or(0.0);
        let state = property(&bus, upower, device, iface, "State").await.and_then(|v| u32::try_from(v).ok()).unwrap_or(0);
        Some((percent, state))
    } else {
        None
    };
    Conditions { metered, battery, idle }
}

enum Action {
    Settings,
    Download,
    Restart,
    Tonight,
}

/// The news as notifications from "Software update", the way Android's
/// system update channel shows them: one at a time, each replacing the
/// last, and a tap opens Settings → Software updates. A download is one
/// ongoing row with its progress until the restart notice takes its place.
struct Notifier {
    id: u32,
    /// What the progress row shows: percent and whether it is installing.
    shown: Option<(i32, bool)>,
}

impl Notifier {
    fn listen(tx: &Sender<Msg>) {
        let tx = tx.clone();
        io::spawn(async move {
            let actions = async { NotificationsProxy::new(&io::session_bus().await?).await?.receive_action_invoked().await };
            let mut actions = match actions.await {
                Ok(actions) => actions,
                Err(e) => return log::warn("updates", format_args!("no notification actions: {e}")),
            };
            while let Some(signal) = actions.next().await {
                if let Ok(args) = signal.args() {
                    tx.send(Msg::Action(args.id, args.action_key)).await.ok();
                }
            }
        });
    }

    fn action(&self, id: u32, action: &str) -> Option<Action> {
        if id == 0 || id != self.id {
            return None;
        }
        match action {
            "default" => Some(Action::Settings),
            "download" => Some(Action::Download),
            "restart" => Some(Action::Restart),
            "tonight" => Some(Action::Tonight),
            _ => None,
        }
    }

    async fn post(&mut self, m: &Machine, kind: Notice, version: &str) {
        let mut actions = vec!["default", "Open"];
        let (summary, body) = match kind {
            Notice::Available => {
                actions.extend(["download", "Download", "later", "Later"]);
                ("Update available".to_owned(), format!("Marathon {version}"))
            }
            Notice::Restart => {
                actions.extend(["restart", "Restart now"]);
                if !m.startup_pin {
                    actions.extend(["tonight", "Tonight"]);
                }
                let body = if m.restart_scheduled() {
                    format!("Marathon {version} installs tonight while charging.")
                } else {
                    format!("Marathon {version} is ready.")
                };
                ("Restart to finish updating".to_owned(), body)
            }
            Notice::RolledBack => (
                format!("Marathon {version} didn't start"),
                format!("The update couldn't start, so Marathon went back to {}.", m.os_version),
            ),
            Notice::Updated => (format!("Updated to Marathon {version}"), "Tap to see what's new.".to_owned()),
        };
        self.notify(&summary, &body, &actions, None).await;
    }

    /// Only a new percent or phase reaches the Hub. A finished download's
    /// row goes first, so the restart notice that follows is a fresh one.
    async fn show_progress(&mut self, m: &Machine) {
        if m.state != State::Downloading {
            if self.shown.take().is_some() {
                if let Err(e) = async { NotificationsProxy::new(&io::session_bus().await?).await?.close_notification(self.id).await }.await {
                    log::warn("updates", format_args!("closing the progress row: {e}"));
                }
            }
            return;
        }
        let now = (m.progress, m.installing);
        if self.shown == Some(now) {
            return;
        }
        self.shown = Some(now);
        let summary = if m.installing { "Installing update" } else { "Downloading update" };
        let body = format!("Marathon OS {} · {}%", m.available, m.progress);
        self.notify(summary, &body, &["default", "Open"], Some(m.progress)).await;
    }

    async fn notify(&mut self, summary: &str, body: &str, actions: &[&str], percent: Option<i32>) {
        let hints = percent.map(|p| ("value", Value::from(p))).into_iter().collect();
        let sent = async {
            NotificationsProxy::new(&io::session_bus().await?)
                .await?
                .notify("Software update", self.id, "arrow-circle-up", summary, body, actions, hints, -1)
                .await
        };
        match sent.await {
            Ok(id) => self.id = id,
            Err(e) => log::warn("updates", format_args!("notifying: {e}")),
        }
    }
}

/// The view as Updates1 sends it, with the shell's version.
fn wire(view: &serde_json::Value) -> ipc::State {
    let mut state: ipc::State = view
        .as_object()
        .into_iter()
        .flatten()
        .filter_map(|(k, v)| {
            let v = match v {
                serde_json::Value::Bool(b) => value(*b),
                serde_json::Value::String(s) => value(s.clone()),
                serde_json::Value::Number(n) => match n.as_i64() {
                    Some(n) => i32::try_from(n).map_or_else(|_| value(n), value),
                    None => value(n.as_f64().unwrap_or_default()),
                },
                _ => return None,
            };
            Some((k.clone(), v))
        })
        .collect();
    state.insert("currentVersion".to_owned(), value(option_env!("MARATHON_VERSION").unwrap_or(env!("CARGO_PKG_VERSION"))));
    state
}

struct Updates1 {
    qt: Qt,
}

#[zbus::interface(name = "org.marathonos.Shell.Updates1")]
impl Updates1 {
    async fn get_state(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<ipc::State> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| wire(&obj.json)).await
    }

    async fn check_now(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.check_now()).await
    }

    async fn install(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.install()).await
    }

    async fn cancel(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.cancel()).await
    }

    async fn reboot(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.reboot()).await
    }

    async fn schedule_restart(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.schedule_restart()).await
    }

    async fn set_auto_update(&self, on: bool, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Updates", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_auto_update(on)).await
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    const OS: &str = "26101701";
    const NEW: &str = "26101801";

    fn machine(saved: Saved) -> Machine {
        let mut m = Machine::new(OS.into(), "boot-b".into(), saved);
        m.conditions.idle = true;
        m
    }

    fn idle() -> Machine {
        let mut m = machine(Saved { last_seen_version: OS.into(), ..Saved::default() });
        m.probed(true, OS);
        m.effects.clear();
        m
    }

    type Notices<'a> = Vec<(Notice, &'a str)>;

    fn notices(m: &Machine) -> Notices<'_> {
        m.effects.iter().filter_map(|e| if let Effect::Notice(k, v) = e { Some((*k, v.as_str())) } else { None }).collect()
    }

    #[test]
    fn without_a_host_target_or_an_image_it_is_unsupported() {
        let mut m = machine(Saved::default());
        assert!(!m.probed(false, ""));
        assert_eq!(m.state, State::Unsupported);
        let mut m = Machine::new(String::new(), "b".into(), Saved::default());
        m.probed(true, NEW);
        assert_eq!(m.state, State::Unsupported);
    }

    #[test]
    fn a_found_update_downloads_by_itself_on_wifi() {
        let mut m = idle();
        m.check_now();
        assert_eq!(m.effects, [Effect::Check]);
        m.effects.clear();
        m.checked(NEW);
        assert_eq!(m.state, State::Downloading);
        assert!(m.effects.contains(&Effect::Install) && m.effects.contains(&Effect::Info(NEW.into())));
        assert_eq!(notices(&m), Notices::new());
    }

    #[test]
    fn a_metered_network_holds_the_download_and_announces_it_once() {
        let mut m = idle();
        m.conditions.metered = 3;
        m.check_now();
        m.checked(NEW);
        assert_eq!((m.state, m.blocked), (State::Available, "metered"));
        assert_eq!(notices(&m), [(Notice::Available, NEW)]);
        m.effects.clear();
        m.check_now();
        m.checked(NEW);
        assert_eq!(notices(&m), Notices::new());
        m.conditions.metered = 0;
        m.auto_install();
        assert_eq!(m.state, State::Downloading);
    }

    #[test]
    fn a_low_battery_blocks_unless_charging() {
        let low = Conditions { battery: Some((20.0, 2)), ..Conditions::default() };
        assert_eq!(low.block_reason(), "battery");
        assert_eq!(Conditions { battery: Some((20.0, 1)), ..low }.block_reason(), "");
        assert_eq!(Conditions { battery: Some((31.0, 2)), ..low }.block_reason(), "");
        assert_eq!(Conditions::default().block_reason(), "");
    }

    #[test]
    fn a_finished_install_waits_for_a_restart_and_is_saved() {
        let mut m = idle();
        m.check_now();
        m.checked(NEW);
        m.progressed(40);
        m.installing();
        assert_eq!((m.progress, m.installing), (0, true));
        m.installed(NEW);
        assert_eq!(m.state, State::ReadyToReboot);
        assert_eq!((m.saved.installed_version.as_str(), m.saved.installed_boot_id.as_str()), (NEW, "boot-b"));
        assert_eq!(notices(&m), [(Notice::Restart, NEW)]);
    }

    #[test]
    fn a_cancelled_download_does_not_start_again_by_itself() {
        let mut m = idle();
        m.check_now();
        m.checked(NEW);
        m.cancel();
        assert_eq!(m.state, State::Available);
        assert!(m.effects.contains(&Effect::Cancel));
        m.failed("cancelled".into());
        assert_eq!(m.state, State::Available);
        assert!(!m.auto_install());
    }

    #[test]
    fn a_failed_check_is_an_error_you_can_retry() {
        let mut m = idle();
        m.check_now();
        m.failed("offline".into());
        assert_eq!((m.state, m.error.as_str()), (State::Error, "offline"));
        assert!(m.saved.last_checked > 0);
        m.check_now();
        assert_eq!((m.state, m.error.as_str()), (State::Checking, ""));
    }

    #[test]
    fn an_image_we_installed_last_boot_that_is_not_running_rolled_back() {
        let saved = Saved { installed_version: NEW.into(), installed_boot_id: "boot-a".into(), last_seen_version: OS.into(), ..Saved::default() };
        let mut m = machine(saved.clone());
        m.probed(true, NEW);
        assert_eq!((m.state, m.rolled_back.as_str()), (State::RolledBack, NEW));
        assert_eq!(notices(&m), [(Notice::RolledBack, NEW)]);
        // The next shell start says nothing new.
        let mut again = machine(m.saved.clone());
        again.probed(true, NEW);
        assert_eq!(notices(&again), Notices::new());
        // Installed this boot: it waits for the restart.
        let mut m = machine(Saved { installed_boot_id: "boot-b".into(), ..saved });
        m.probed(true, NEW);
        assert_eq!((m.state, m.available.as_str()), (State::ReadyToReboot, NEW));
    }

    #[test]
    fn a_boot_into_a_new_version_is_announced_once() {
        let mut m = machine(Saved { last_seen_version: "26101601".into(), ..Saved::default() });
        m.probed(true, OS);
        assert_eq!(notices(&m), [(Notice::Updated, OS)]);
        assert!(m.effects.contains(&Effect::Info(OS.into())));
        let mut first = machine(Saved::default());
        first.probed(true, OS);
        assert_eq!(notices(&first), Notices::new(), "the first boot is no update");
        let mut ours = machine(Saved { installed_version: OS.into(), ..Saved::default() });
        ours.probed(true, OS);
        assert_eq!(notices(&ours), [(Notice::Updated, OS)], "an install from before lastSeenVersion was kept");
    }

    #[test]
    fn the_overnight_restart_needs_the_window_idle_and_charge() {
        let mut m = idle();
        m.check_now();
        m.checked(NEW);
        m.installed(NEW);
        assert!(m.restart_now(3));
        assert!(!m.restart_now(5) && !m.restart_now(1));
        m.conditions.battery = Some((90.0, 2));
        assert!(!m.restart_now(3));
        m.conditions.battery = Some((90.0, 4));
        m.conditions.idle = false;
        assert!(!m.restart_now(3));
        m.conditions.idle = true;
        m.startup_pin = true;
        assert!(!m.restart_scheduled(), "a startup PIN would wait at the prompt");
    }

    #[test]
    fn tonight_schedules_the_restart_without_automatic_updates() {
        let mut m = idle();
        m.set_auto_update(false);
        m.check_now();
        m.checked(NEW);
        assert_eq!(m.state, State::Available);
        m.conditions.metered = 0;
        m.install();
        m.installed(NEW);
        assert!(!m.restart_scheduled());
        m.schedule_restart();
        assert!(m.restart_scheduled());
    }

    #[test]
    fn os_release_and_app_stream_parse() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("os-release");
        std::fs::write(&path, "NAME=Marathon\nIMAGE_VERSION=\"26101801\"\n").unwrap();
        assert_eq!(image_version(&path), NEW);
        let xml = br#"<component><releases>
            <release version="26101701"><size type="download">5</size><description><p>Old</p></description></release>
            <release version="26101801"><size type="download">100</size><size type="installed">900</size><size type="download">20</size>
              <description><p>Faster   apps.</p><ul><li>Maps</li></ul></description></release>
        </releases></component>"#;
        assert_eq!(app_stream(xml, NEW), Some((120, "Faster apps.\n• Maps".to_owned())));
        assert_eq!(app_stream(xml, "none"), Some((-1, String::new())));
    }

    #[test]
    fn the_qt_settings_carry_over() {
        let dir = tempfile::tempdir().unwrap();
        let conf = dir.path().join("Marathon Shell.conf");
        std::fs::write(&conf, "[General]\nx=1\n\n[updates]\nautoUpdate=false\ninstalledVersion=26101801\nnotice\\Restart=26101801\nnoticeId=7\n\n[other]\nautoUpdate=true\n").unwrap();
        let saved = Saved::from_qsettings(&conf);
        assert!(saved.manual);
        assert_eq!((saved.installed_version.as_str(), saved.notice_id), (NEW, 7));
        assert_eq!(saved.notices.get("Restart").map(String::as_str), Some(NEW));
    }
}
