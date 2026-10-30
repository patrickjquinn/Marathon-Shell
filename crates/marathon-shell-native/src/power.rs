//! Battery and its warnings, power profiles, wakelocks, wake-ups, the power
//! key, sleep and the power actions. QML and the shell's C++ see the
//! `QObject` `Power`; everything that talks to `UPower`, logind,
//! power-profiles-daemon, systemd or sysfs runs in one actor on the I/O
//! thread, and each power key is read on its own.

use crate::i18n::fl;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::pin::Pin;
use std::sync::{LazyLock, Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QStringList};
use evdev::{EventSummary, KeyCode};
use futures_lite::{stream, StreamExt};
use zbus::fdo::{self, DBusProxy, PropertiesProxy};
use zbus::message::Header;
use zbus::names::InterfaceName;
use zbus::{OwnedFd, OwnedVariant as OwnedValue, Variant as Value};

use crate::ipc::{self, value, State};
use crate::wake_timer::WakeTimer;
use crate::{display, io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(i32, battery_level, cxx_name = "batteryLevel", READ, NOTIFY)]
        #[qproperty(u32, warning_level, cxx_name = "warningLevel", READ, NOTIFY)]
        #[qproperty(bool, is_charging, cxx_name = "isCharging", READ, NOTIFY)]
        #[qproperty(bool, is_plugged_in, cxx_name = "isPluggedIn", READ, NOTIFY)]
        #[qproperty(bool, is_power_save_mode, cxx_name = "isPowerSaveMode", READ, NOTIFY)]
        #[qproperty(
            i32,
            estimated_battery_time,
            cxx_name = "estimatedBatteryTime",
            READ,
            NOTIFY
        )]
        #[qproperty(QString, power_profile, cxx_name = "powerProfile", READ, NOTIFY)]
        #[qproperty(
            bool,
            power_profiles_supported,
            cxx_name = "powerProfilesSupported",
            READ,
            NOTIFY
        )]
        #[qproperty(
            QStringList,
            active_wakelocks,
            cxx_name = "activeWakelocks",
            READ,
            NOTIFY
        )]
        #[qproperty(i32, wake_lock_count, cxx_name = "wakeLockCount", READ, NOTIFY)]
        #[qproperty(QString, critical_action, cxx_name = "criticalAction", READ, NOTIFY)]
        #[qproperty(
            bool,
            has_active_calls,
            cxx_name = "hasActiveCalls",
            READ,
            WRITE,
            NOTIFY
        )]
        type Power = super::PowerRust;

        #[qsignal]
        #[cxx_name = "batteryWarning"]
        fn battery_warning(
            self: Pin<&mut Self>,
            title: &QString,
            body: &QString,
            icon: &QString,
            haptic: i32,
        );
        /// The critical action runs in `seconds` unless a charger comes.
        #[qsignal]
        #[cxx_name = "emergencyShutdownArmed"]
        fn emergency_shutdown_armed(self: Pin<&mut Self>, seconds: i32);
        #[qsignal]
        #[cxx_name = "emergencyShutdownDisarmed"]
        fn emergency_shutdown_disarmed(self: Pin<&mut Self>);
        /// `device` is the input node: "<name> (<path>)".
        #[qsignal]
        #[cxx_name = "powerKeyPressed"]
        fn power_key_pressed(self: Pin<&mut Self>, device: &QString);
        #[qsignal]
        #[cxx_name = "powerKeyReleased"]
        fn power_key_released(self: Pin<&mut Self>, device: &QString);
        /// Whether systemd took the wake-up `setWakeTimer` asked for.
        #[qsignal]
        #[cxx_name = "wakeTimerSet"]
        fn wake_timer_set(self: Pin<&mut Self>, key: &QString, ok: bool);
        #[qsignal]
        #[cxx_name = "powerError"]
        fn power_error(self: Pin<&mut Self>, message: &QString);
        /// The system woke; `background_wake` when marathon-background armed it.
        #[qsignal]
        #[cxx_name = "resumedFromSuspend"]
        fn resumed_from_suspend(self: Pin<&mut Self>, background_wake: bool);

        #[qinvokable]
        fn suspend(self: &Power);
        #[qinvokable]
        fn hibernate(self: &Power);
        #[qinvokable]
        #[cxx_name = "hybridSleep"]
        fn hybrid_sleep(self: &Power);
        #[qinvokable]
        fn shutdown(self: &Power);
        #[qinvokable]
        fn restart(self: &Power);
        #[qinvokable]
        #[cxx_name = "setPowerSaveMode"]
        fn set_power_save_mode(self: Pin<&mut Power>, enabled: bool);
        #[qinvokable]
        #[cxx_name = "setPowerProfile"]
        fn set_power_profile(self: &Power, profile: &QString);
        #[qinvokable]
        #[cxx_name = "acquireWakelock"]
        fn acquire_wakelock(self: Pin<&mut Power>, name: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "releaseWakelock"]
        fn release_wakelock(self: Pin<&mut Power>, name: &QString) -> bool;
        /// Replaces the shell's own sleep delay lock with one for `who`.
        #[qinvokable]
        #[cxx_name = "inhibitSuspend"]
        fn inhibit_suspend(self: &Power, who: &QString, why: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "releaseInhibitor"]
        fn release_inhibitor(self: &Power);
        /// Wakes a suspended device at `epoch_secs` for `key`, replacing its
        /// last wake-up; 0 for none. The key "alarm" is the alarm clock's.
        #[qinvokable]
        #[cxx_name = "setWakeTimer"]
        fn set_wake_timer(self: &Power, key: &QString, epoch_secs: i64);
        /// UPower's critical action: hybrid sleep, hibernate, suspend or, for
        /// anything else, power off.
        #[qinvokable]
        #[cxx_name = "performCriticalPowerAction"]
        fn perform_critical_power_action(self: &Power);
    }

    impl cxx_qt::Threading for Power {}
    impl cxx_qt::Initialize for Power {}
}

use qobject::Power;

#[path = "battery_measurement.rs"]
mod measurement;

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct PowerRust {
    battery_level: i32,
    warning_level: u32,
    is_charging: bool,
    is_plugged_in: bool,
    is_power_save_mode: bool,
    estimated_battery_time: i32,
    power_profile: QString,
    power_profiles_supported: bool,
    active_wakelocks: QStringList,
    wake_lock_count: i32,
    critical_action: QString,
    profile_before_saver: Option<String>,
    has_active_calls: bool,
    /// The level last warned at, 100 for none since charging.
    warned_at: i32,
    shutdown_armed: bool,
    held: BTreeSet<String>,
    actor: Option<Sender<Command>>,
}

impl Default for PowerRust {
    fn default() -> Self {
        Self {
            battery_level: -1,
            warning_level: 0,
            is_charging: false,
            is_plugged_in: true,
            is_power_save_mode: false,
            estimated_battery_time: -1,
            power_profile: QString::from("balanced"),
            power_profiles_supported: false,
            active_wakelocks: QStringList::default(),
            wake_lock_count: 0,
            critical_action: QString::from("PowerOff"),
            profile_before_saver: None,
            has_active_calls: false,
            warned_at: 100,
            shutdown_armed: false,
            held: BTreeSet::new(),
            actor: None,
        }
    }
}

enum Command {
    Wakelock(String, bool),
    Inhibit(String, String),
    ReleaseInhibitor,
    Act(Action),
    Profile(String),
    WakeTimer(String, i64),
}

#[derive(Clone, Copy)]
enum Action {
    Suspend,
    Hibernate,
    HybridSleep,
    PowerOff,
    Reboot,
}

impl cxx_qt::Initialize for Power {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(64);
        let qt = self.qt_thread();
        POWER.set(qt.clone()).ok();
        ipc::export("Power", Power1 { qt: qt.clone() });
        watch_power_keys(qt.clone());
        io::spawn(run(qt, rx));
        self.as_mut().rust_mut().actor = Some(tx);
    }
}

impl Power {
    fn send(&self, command: Command) -> bool {
        self.actor
            .as_ref()
            .is_some_and(|a| a.try_send(command).is_ok())
    }

    fn act(&self, action: Action) {
        if !self.send(Command::Act(action)) {
            log::warn("power", "no power backend");
        }
    }

    fn suspend(&self) {
        self.act(Action::Suspend);
    }

    fn hibernate(&self) {
        self.act(Action::Hibernate);
    }

    fn hybrid_sleep(&self) {
        self.act(Action::HybridSleep);
    }

    fn shutdown(&self) {
        self.act(Action::PowerOff);
    }

    fn restart(&self) {
        self.act(Action::Reboot);
    }

    // Saver is the power-saver profile; leaving it restores the profile from
    // before. It never enables suspend: Doze is the low-power path.
    fn set_power_save_mode(mut self: Pin<&mut Self>, enabled: bool) {
        if self.is_power_save_mode == enabled {
            return;
        }
        let profile = if enabled {
            let current = self.power_profile.to_string();
            self.as_mut().rust_mut().profile_before_saver = Some(current);
            "power-saver".to_owned()
        } else {
            self.as_mut()
                .rust_mut()
                .profile_before_saver
                .take()
                .unwrap_or_else(|| "balanced".to_owned())
        };
        self.request_profile(&profile);
        self.as_mut().rust_mut().is_power_save_mode = enabled;
        self.is_power_save_mode_changed();
        state_changed();
    }

    fn set_power_profile(&self, profile: &QString) {
        self.request_profile(&profile.to_string());
    }

    fn request_profile(&self, profile: &str) {
        let name = match profile {
            "performance" => "performance",
            "power-saver" | "powersave" => "power-saver",
            _ => "balanced",
        };
        if !self.power_profiles_supported {
            return log::warn(
                "power",
                format_args!("no power profile service; cannot set {name}"),
            );
        }
        self.send(Command::Profile(name.to_owned()));
    }

    fn acquire_wakelock(mut self: Pin<&mut Self>, name: &QString) -> bool {
        let name = name.to_string();
        if self.held.contains(&name) {
            return true;
        }
        if !self.send(Command::Wakelock(name.clone(), true)) {
            return false;
        }
        self.as_mut().rust_mut().held.insert(name);
        self.wakelocks_changed();
        true
    }

    fn release_wakelock(mut self: Pin<&mut Self>, name: &QString) -> bool {
        let name = name.to_string();
        if !self.as_mut().rust_mut().held.remove(&name) {
            return true;
        }
        self.send(Command::Wakelock(name, false));
        self.wakelocks_changed();
        true
    }

    fn wakelocks_changed(mut self: Pin<&mut Self>) {
        let mut names = QList::<QString>::default();
        for name in &self.held {
            names.append(QString::from(name.as_str()));
        }
        let count = i32::try_from(self.held.len()).unwrap_or(i32::MAX);
        let mut rust = self.as_mut().rust_mut();
        rust.active_wakelocks = QStringList::from(&names);
        rust.wake_lock_count = count;
        self.as_mut().wake_lock_count_changed();
        self.active_wakelocks_changed();
    }

    fn inhibit_suspend(&self, who: &QString, why: &QString) -> bool {
        self.send(Command::Inhibit(who.to_string(), why.to_string()))
    }

    fn release_inhibitor(&self) {
        self.send(Command::ReleaseInhibitor);
    }

    fn set_wake_timer(&self, key: &QString, epoch_secs: i64) {
        self.send(Command::WakeTimer(key.to_string(), epoch_secs));
    }

    fn perform_critical_power_action(&self) {
        if !measurement::known(self.battery_level) {
            return log::warn(
                "power",
                "critical action refused: battery percentage unavailable",
            );
        }
        let action = self.critical_action.to_string().to_ascii_lowercase();
        log::warn("power", format_args!("critical battery: {action}"));
        self.act(match action.as_str() {
            "hybridsleep" => Action::HybridSleep,
            "hibernate" => Action::Hibernate,
            "suspend" => Action::Suspend,
            _ => Action::PowerOff,
        });
    }

    /// Warns once per threshold on the way down, and arms the critical
    /// action at `UPower`'s critical level; a charger resets both.
    fn warn_battery(mut self: Pin<&mut Self>) {
        let (level, warning) = (self.battery_level, self.warning_level);
        if !measurement::known(level) {
            self.as_mut().rust_mut().warned_at = 100;
            if self.shutdown_armed {
                self.as_mut().rust_mut().shutdown_armed = false;
                self.emergency_shutdown_disarmed();
            }
            return;
        }
        if self.is_charging || warning < 4 {
            if self.shutdown_armed {
                self.as_mut().rust_mut().shutdown_armed = false;
                self.as_mut().emergency_shutdown_disarmed();
            }
            if self.is_charging {
                self.as_mut().rust_mut().warned_at = 100;
                return;
            }
        }
        let Some(Warning {
            at,
            title,
            body,
            icon,
            haptic,
        }) = battery_warning(
            level,
            warning,
            self.warned_at,
            &self.critical_action.to_string(),
        )
        else {
            return;
        };
        self.as_mut().rust_mut().warned_at = at;
        self.as_mut().battery_warning(
            &QString::from(&title),
            &QString::from(&body),
            &QString::from(icon),
            haptic,
        );
        if measurement::can_arm_shutdown(level, warning, self.is_charging) && !self.shutdown_armed {
            self.as_mut().rust_mut().shutdown_armed = true;
            self.emergency_shutdown_armed(10);
        }
    }

    fn apply_battery(mut self: Pin<&mut Self>, battery: Battery) {
        let before = state(&self);
        let level = battery.level();
        if self.battery_level != level {
            self.as_mut().rust_mut().battery_level = level;
            self.as_mut().battery_level_changed();
        }
        if self.warning_level != battery.warning {
            self.as_mut().rust_mut().warning_level = battery.warning;
            self.as_mut().warning_level_changed();
        }
        let charging = battery.is_charging();
        if self.is_charging != charging {
            self.as_mut().rust_mut().is_charging = charging;
            self.as_mut().is_charging_changed();
        }
        let plugged_in = battery.is_plugged_in();
        if self.is_plugged_in != plugged_in {
            self.as_mut().rust_mut().is_plugged_in = plugged_in;
            self.as_mut().is_plugged_in_changed();
        }
        let minutes = battery.estimated_minutes();
        if self.estimated_battery_time != minutes {
            self.as_mut().rust_mut().estimated_battery_time = minutes;
            self.as_mut().estimated_battery_time_changed();
        }
        if state(&self) != before {
            state_changed();
        }
        self.warn_battery();
    }

    fn apply_profile(mut self: Pin<&mut Self>, profile: &str) {
        let before = state(&self);
        if !self.power_profiles_supported || self.power_profile.to_string() != profile {
            let mut rust = self.as_mut().rust_mut();
            rust.power_profiles_supported = true;
            rust.power_profile = QString::from(profile);
            self.as_mut().power_profile_changed();
            self.as_mut().power_profiles_supported_changed();
        }
        let saver = profile == "power-saver";
        if self.is_power_save_mode != saver {
            self.as_mut().rust_mut().is_power_save_mode = saver;
            self.as_mut().is_power_save_mode_changed();
        }
        if state(&self) != before {
            state_changed();
        }
    }

    fn apply_critical_action(mut self: Pin<&mut Self>, action: &str) {
        if self.critical_action.to_string() != action {
            self.as_mut().rust_mut().critical_action = QString::from(action);
            self.critical_action_changed();
        }
    }
}

struct Warning {
    /// The level it warns at; it warns again only below it.
    at: i32,
    title: String,
    body: String,
    icon: &'static str,
    haptic: i32,
}

/// The warning due at `level` and `UPower`'s `warning`, after one at `warned_at`.
fn battery_warning(
    level: i32,
    warning: u32,
    warned_at: i32,
    critical_action: &str,
) -> Option<Warning> {
    if !measurement::known(level) {
        return None;
    }
    let warn = |at, title, body, icon, haptic| {
        Some(Warning {
            at,
            title,
            body,
            icon,
            haptic,
        })
    };
    match warning {
        4.. if warned_at > 3 => warn(
            level.min(3),
            fl!("battery-critical-title"),
            fl!("battery-critical-body", action = critical_action),
            "battery-warning",
            3,
        ),
        3 if warned_at > 20 => warn(
            20,
            fl!("battery-low-title"),
            fl!("battery-low-body", level = level),
            "battery",
            1,
        ),
        0..=2 if level >= 0 && level <= 5 && warned_at > 5 => warn(
            5,
            fl!("battery-very-low-title"),
            fl!("battery-very-low-body", level = level),
            "battery-warning",
            3,
        ),
        0..=2 if level >= 0 && level <= 10 && warned_at > 10 => warn(
            10,
            fl!("battery-lower-title"),
            fl!("battery-lower-body", level = level),
            "battery",
            2,
        ),
        0..=2 if level >= 0 && level <= 20 && warned_at > 20 => warn(
            20,
            fl!("battery-low-title"),
            fl!("battery-low-body", level = level),
            "battery",
            1,
        ),
        _ => None,
    }
}

/// Reads every input device with a power key on a thread of its own: the
/// key wakes the screen, so it never waits behind other I/O.
fn watch_power_keys(qt: Qt) {
    let found = std::thread::Builder::new().name("marathon-keys".into()).spawn(move || {
        let keys = evdev::enumerate().filter(|(_, d)| d.supported_keys().is_some_and(|k| k.contains(KeyCode::KEY_POWER)));
        let mut watched = 0;
        for (path, mut device) in keys {
            let name = format!("{} ({})", device.name().unwrap_or("?"), path.display());
            let qt = qt.clone();
            let read = move || loop {
                let events = match device.fetch_events() {
                    Ok(events) => events,
                    Err(e) => return log::warn("power", format_args!("{name}: {e}")),
                };
                for event in events {
                    if let EventSummary::Key(_, KeyCode::KEY_POWER, value @ 0..=1) = event.destructure() {
                        let device = QString::from(name.as_str());
                        qt.queue(move |obj| {
                            if value == 1 {
                                obj.power_key_pressed(&device);
                            } else {
                                obj.power_key_released(&device);
                            }
                        })
                        .ok();
                    }
                }
            };
            match std::thread::Builder::new().name("marathon-powerkey".into()).spawn(read) {
                Ok(_) => watched += 1,
                Err(e) => log::warn("power", format_args!("cannot read a power key: {e}")),
            }
        }
        if watched == 0 {
            log::warn("power", "no input device has a power key the shell can read; the power button will not wake the display");
        }
    });
    if let Err(e) = found {
        log::warn("power", format_args!("cannot look for power keys: {e}"));
    }
}

/// `UPower`'s `DisplayDevice`, as its properties last said.
#[derive(Clone, Copy, Default)]
struct Battery {
    percentage: Option<f64>,
    percentage_available: bool,
    state: u32,
    warning: u32,
    time_to_empty: i64,
    time_to_full: i64,
}

impl Battery {
    // UPower's states: 1 charging, 2 discharging, 4 fully charged,
    // 5 pending charge, 6 pending discharge.
    fn level(self) -> i32 {
        measurement::level(self.percentage, self.percentage_available)
    }

    fn is_charging(self) -> bool {
        matches!(self.state, 1 | 5)
    }

    fn is_plugged_in(self) -> bool {
        matches!(self.state, 1 | 4 | 5)
    }

    fn estimated_minutes(self) -> i32 {
        if !measurement::known(self.level()) {
            return -1;
        }
        let seconds = match self.state {
            2 | 6 => self.time_to_empty,
            1 | 5 => self.time_to_full,
            _ => 0,
        };
        if seconds > 0 {
            i32::try_from(seconds / 60).unwrap_or(i32::MAX)
        } else {
            -1
        }
    }

    // Invalidated values are unavailable until UPower sends a fresh value.
    fn invalidate(&mut self, name: &str) {
        match name {
            "Percentage" => self.percentage = None,
            "TimeToEmpty" => self.time_to_empty = 0,
            "TimeToFull" => self.time_to_full = 0,
            "State" => self.state = 0,
            "WarningLevel" => self.warning = 0,
            _ => {}
        }
    }

    fn set(&mut self, name: &str, value: &Value<'_>) {
        match name {
            "Percentage" => self.percentage = value.downcast_ref().ok(),
            "State" => self.state = value.downcast_ref().unwrap_or(self.state),
            "WarningLevel" => self.warning = value.downcast_ref().unwrap_or(self.warning),
            "TimeToEmpty" => {
                self.time_to_empty = value.downcast_ref().unwrap_or(self.time_to_empty);
            }
            "TimeToFull" => self.time_to_full = value.downcast_ref().unwrap_or(self.time_to_full),
            _ => {}
        }
    }
}

/// Whether a resume at `now` is the wake-up marathon-background armed (its
/// time is in `marker`), not one for the alarm due at `alarm` or one the
/// person caused.
fn is_background_wake(marker: &str, alarm: i64, now: i64) -> bool {
    let woke_for = |t: i64| (t - 10..=t + 60).contains(&now);
    if alarm > 0 && woke_for(alarm) {
        return false;
    }
    io::read::<i64>(marker).is_some_and(woke_for)
}

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
pub(crate) trait Logind {
    fn inhibit(&self, what: &str, who: &str, why: &str, mode: &str) -> zbus::Result<OwnedFd>;
    fn suspend(&self, interactive: bool) -> zbus::Result<()>;
    fn hibernate(&self, interactive: bool) -> zbus::Result<()>;
    fn hybrid_sleep(&self, interactive: bool) -> zbus::Result<()>;
    fn power_off(&self, interactive: bool) -> zbus::Result<()>;
    fn reboot(&self, interactive: bool) -> zbus::Result<()>;
    #[zbus(signal)]
    fn prepare_for_sleep(&self, start: bool) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.UPower",
    default_service = "org.freedesktop.UPower",
    default_path = "/org/freedesktop/UPower"
)]
trait UPower {
    fn get_critical_action(&self) -> zbus::Result<String>;
}

const UPOWER: &str = "org.freedesktop.UPower";
const DISPLAY_DEVICE: &str = "/org/freedesktop/UPower/devices/DisplayDevice";
const DEVICE: &str = "org.freedesktop.UPower.Device";
const PROFILES: &str = "org.freedesktop.UPower.PowerProfiles";
const PROFILES_PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
const WAKE_LOCK: &str = "/sys/power/wake_lock";
const WAKE_UNLOCK: &str = "/sys/power/wake_unlock";
const BACKGROUND_WAKE_MARKER: &str = "/run/marathon-background/wake";

type Qt = cxx_qt::CxxQtThread<Power>;

enum Event {
    Command(Command),
    Closed,
    Sleep(bool),
    Battery(Vec<(String, OwnedValue)>, Vec<String>),
    Profile(Option<String>),
}

/// Everything on the system side: the locks it holds and the streams it reads.
struct Actor {
    bus: zbus::Connection,
    logind: LogindProxy<'static>,
    lifelong: Option<OwnedFd>,
    // Kernel wakelocks hold nothing here; logind's fallback holds an fd.
    wakelocks: BTreeMap<String, Option<OwnedFd>>,
    kernel_wakelocks: bool,
    battery: Battery,
    alarm: i64,
    wake_timers: HashMap<String, WakeTimer>,
}

async fn run(qt: Qt, commands: Receiver<Command>) {
    let bus = match io::system_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("power", format_args!("no system bus: {e}")),
    };
    let logind = match LogindProxy::new(&bus).await {
        Ok(l) => l,
        Err(e) => return log::warn("power", format_args!("no logind: {e}")),
    };
    let mut actor = Actor {
        bus,
        logind,
        lifelong: None,
        wakelocks: BTreeMap::new(),
        kernel_wakelocks: std::fs::OpenOptions::new()
            .write(true)
            .open(WAKE_LOCK)
            .is_ok(),
        battery: Battery::default(),
        alarm: 0,
        wake_timers: HashMap::new(),
    };
    actor.lifelong = actor.inhibit("marathon-shell", "Handle wake events").await;
    actor.read_critical_action(&qt).await;
    actor.read_battery(&qt).await;
    // tuned-ppd is deliberately delayed until after the interactive boot.
    // Merely reading its property would D-Bus-activate tuned here and put its
    // expensive Python startup back on the shell's critical path.
    if actor.profile_service_running().await {
        actor.read_profile(&qt).await;
    }

    let events = commands
        .map(Event::Command)
        .chain(stream::once(Event::Closed))
        .or(actor.sleep_events().await)
        .or(actor.battery_events().await)
        .or(actor.profile_events().await);
    let mut events = std::pin::pin!(events);
    while let Some(event) = events.next().await {
        match event {
            Event::Command(command) => actor.handle(&qt, command).await,
            Event::Closed => break,
            Event::Sleep(before) => actor.on_sleep(&qt, before).await,
            Event::Battery(changed, invalidated) => {
                for (name, value) in &changed {
                    actor.battery.set(name, value);
                }
                for name in &invalidated {
                    actor.battery.invalidate(name);
                }
                actor.battery.percentage_available =
                    measurement::available(std::path::Path::new("/sys/class/power_supply"));
                let battery = actor.battery;
                qt.queue(move |obj| obj.apply_battery(battery)).ok();
            }
            Event::Profile(Some(profile)) => queue_profile(&qt, profile),
            Event::Profile(None) => actor.read_profile(&qt).await,
        }
    }
    actor.release_all();
}

fn queue_profile(qt: &Qt, profile: String) {
    qt.queue(move |obj| obj.apply_profile(&profile)).ok();
}

impl Actor {
    async fn profile_service_running(&self) -> bool {
        let Ok(dbus) = DBusProxy::new(&self.bus).await else {
            return false;
        };
        let Ok(name) = PROFILES.try_into() else {
            return false;
        };
        dbus.name_has_owner(name).await.unwrap_or(false)
    }

    async fn inhibit(&self, who: &str, why: &str) -> Option<OwnedFd> {
        match self.logind.inhibit("sleep", who, why, "delay").await {
            Ok(fd) => Some(fd),
            Err(e) => {
                log::warn("power", format_args!("no sleep inhibitor for {why}: {e}"));
                None
            }
        }
    }

    async fn handle(&mut self, qt: &Qt, command: Command) {
        match command {
            Command::Wakelock(name, true) => {
                let fd = self.hold(&name).await;
                self.wakelocks.insert(name, fd);
            }
            Command::Wakelock(name, false) => {
                if let Some(None) = self.wakelocks.remove(&name) {
                    write(WAKE_UNLOCK, &name);
                }
            }
            Command::Inhibit(who, why) => self.lifelong = self.inhibit(&who, &why).await,
            Command::ReleaseInhibitor => self.lifelong = None,
            Command::Act(action) => self.act(qt, action).await,
            Command::Profile(name) => self.set_profile(qt, name).await,
            Command::WakeTimer(key, epoch_secs) => {
                if key == "alarm" {
                    self.alarm = epoch_secs;
                }
                let result = self.set_wake_timer(&key, epoch_secs).await;
                if let Err(e) = &result {
                    log::warn("wake", format_args!("setting {key} timer: {e}"));
                }
                let ok = result.is_ok();
                for waiter in WAKES
                    .lock()
                    .unwrap_or_else(|_| std::process::abort())
                    .remove(&key)
                    .unwrap_or_default()
                {
                    waiter.try_send(ok).ok();
                }
                qt.queue(move |obj| obj.wake_timer_set(&QString::from(&key), ok))
                    .ok();
            }
        }
    }

    async fn set_wake_timer(&mut self, key: &str, epoch_secs: i64) -> Result<(), String> {
        if key.is_empty()
            || !key
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "_.-".contains(c))
        {
            return Err(format!("invalid wake-up key {key:?}"));
        }
        let session = io::session_bus()
            .await
            .map_err(|e| format!("no session bus: {e}"))?;
        let timer = self
            .wake_timers
            .entry(key.to_owned())
            .or_insert_with(|| WakeTimer::new(key.to_owned()));
        timer
            .set(&session, epoch_secs)
            .await
            .map_err(|e| e.to_string())
    }

    /// A kernel wakelock if the kernel lets the shell write one, else
    /// logind's delay lock.
    async fn hold(&mut self, name: &str) -> Option<OwnedFd> {
        if self.kernel_wakelocks {
            if write(WAKE_LOCK, name) {
                return None;
            }
            self.kernel_wakelocks = false;
        }
        self.inhibit("Marathon Shell", &format!("Wakelock: {name}"))
            .await
    }

    async fn act(&self, qt: &Qt, action: Action) {
        let (call, what) = match action {
            Action::Suspend => (self.logind.suspend(true).await, "suspend"),
            Action::Hibernate => (self.logind.hibernate(true).await, "hibernate"),
            Action::HybridSleep => (self.logind.hybrid_sleep(true).await, "hybrid sleep"),
            Action::PowerOff => (self.logind.power_off(true).await, "shut down"),
            Action::Reboot => (self.logind.reboot(true).await, "restart"),
        };
        if let Err(e) = call {
            log::warn("power", format_args!("could not {what}: {e}"));
            let message = format!("Failed to {what}");
            qt.queue(move |obj| obj.power_error(&QString::from(message.as_str())))
                .ok();
        }
    }

    async fn on_sleep(&mut self, qt: &Qt, before: bool) {
        if before {
            // Delay locks only delay sleep; let it go now.
            self.lifelong = None;
            for fd in self.wakelocks.values_mut() {
                *fd = None;
            }
            return;
        }
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX));
        let background = is_background_wake(BACKGROUND_WAKE_MARKER, self.alarm, now);
        qt.queue(move |obj| obj.resumed_from_suspend(background))
            .ok();
        let names: Vec<String> = self.wakelocks.keys().cloned().collect();
        for name in names {
            let fd = self.hold(&name).await;
            self.wakelocks.insert(name, fd);
        }
        if self.lifelong.is_none() {
            self.lifelong = self.inhibit("marathon-shell", "Handle wake events").await;
        }
    }

    async fn read_critical_action(&self, qt: &Qt) {
        let Ok(upower) = UPowerProxy::new(&self.bus).await else {
            return;
        };
        match upower.get_critical_action().await {
            Ok(action) if !action.is_empty() => {
                qt.queue(move |obj| obj.apply_critical_action(&action)).ok();
            }
            Ok(_) => {}
            Err(e) => log::warn("power", format_args!("no UPower critical action: {e}")),
        }
    }

    async fn properties(
        &self,
        service: &'static str,
        path: &'static str,
    ) -> Option<PropertiesProxy<'static>> {
        let built = PropertiesProxy::builder(&self.bus)
            .destination(service)
            .path(path)
            .cache_properties(zbus::proxy::CacheProperties::No)
            .build()
            .await;
        match built {
            Ok(props) => Some(props),
            Err(e) => {
                log::warn("power", e);
                None
            }
        }
    }

    // An unavailable percentage stays unknown; charging state remains independent.
    async fn read_battery(&mut self, qt: &Qt) {
        let Some(props) = self.properties(UPOWER, DISPLAY_DEVICE).await else {
            return;
        };
        let Ok(device) = InterfaceName::try_from(DEVICE) else {
            return;
        };
        match props.get_all(device).await {
            Ok(all) => {
                for (name, value) in &all {
                    self.battery.set(name, value);
                }
                self.battery.percentage_available =
                    measurement::available(std::path::Path::new("/sys/class/power_supply"));
                let battery = self.battery;
                qt.queue(move |obj| obj.apply_battery(battery)).ok();
            }
            Err(e) => log::warn("power", format_args!("no battery: {e}")),
        }
    }

    async fn read_profile(&self, qt: &Qt) {
        let Some(props) = self.properties(PROFILES, PROFILES_PATH).await else {
            return;
        };
        let Ok(interface) = InterfaceName::try_from(PROFILES) else {
            return;
        };
        if let Ok(value) = props.get(interface, "ActiveProfile").await {
            if let Ok(profile) = String::try_from(value) {
                queue_profile(qt, profile);
            }
        }
    }

    async fn set_profile(&self, qt: &Qt, name: String) {
        let Some(props) = self.properties(PROFILES, PROFILES_PATH).await else {
            return;
        };
        let Ok(interface) = InterfaceName::try_from(PROFILES) else {
            return;
        };
        // A profile switch runs the daemon's tuning; the I/O thread waits, not the GUI.
        match props
            .set(interface, "ActiveProfile", &Value::from(name.as_str()))
            .await
        {
            Ok(()) => queue_profile(qt, name),
            Err(e) => log::warn("power", format_args!("power profile {name} refused: {e}")),
        }
    }

    async fn sleep_events(&self) -> stream::Boxed<Event> {
        match self.logind.receive_prepare_for_sleep().await {
            Ok(s) => s
                .filter_map(|signal| signal.args().ok().map(|a| Event::Sleep(a.start)))
                .boxed(),
            Err(e) => {
                log::warn("power", format_args!("no sleep signal: {e}"));
                stream::empty().boxed()
            }
        }
    }

    async fn battery_events(&self) -> stream::Boxed<Event> {
        let Some(props) = self.properties(UPOWER, DISPLAY_DEVICE).await else {
            return stream::empty().boxed();
        };
        match props.receive_properties_changed().await {
            Ok(s) => s
                .filter_map(|signal| {
                    let args = signal.args().ok()?;
                    if args.interface_name().as_str() != DEVICE {
                        return None;
                    }
                    let changed = args
                        .changed_properties()
                        .iter()
                        .filter_map(|(k, v)| Some(((*k).to_owned(), v.try_to_owned().ok()?)))
                        .collect();
                    let invalidated = args
                        .invalidated_properties()
                        .iter()
                        .map(|name| (*name).to_owned())
                        .collect();
                    Some(Event::Battery(changed, invalidated))
                })
                .boxed(),
            Err(_) => stream::empty().boxed(),
        }
    }

    // ActiveProfile changes, and a restarted daemon (read afresh).
    async fn profile_events(&self) -> stream::Boxed<Event> {
        let changes = match self.properties(PROFILES, PROFILES_PATH).await {
            Some(props) => match props.receive_properties_changed().await {
                Ok(s) => s
                    .filter_map(|signal| {
                        let args = signal.args().ok()?;
                        let profile = args.changed_properties().get("ActiveProfile")?;
                        Some(Event::Profile(Some(
                            String::try_from(profile.try_to_owned().ok()?).ok()?,
                        )))
                    })
                    .boxed(),
                Err(_) => stream::empty().boxed(),
            },
            None => stream::empty().boxed(),
        };
        let appeared = match DBusProxy::new(&self.bus).await {
            Ok(dbus) => match dbus
                .receive_name_owner_changed_with_args(&[(0, PROFILES)])
                .await
            {
                Ok(s) => s
                    .filter_map(|signal| {
                        let args = signal.args().ok()?;
                        args.new_owner().is_some().then_some(Event::Profile(None))
                    })
                    .boxed(),
                Err(_) => stream::empty().boxed(),
            },
            Err(_) => stream::empty().boxed(),
        };
        changes.or(appeared).boxed()
    }

    fn release_all(&mut self) {
        for (name, fd) in std::mem::take(&mut self.wakelocks) {
            if fd.is_none() {
                write(WAKE_UNLOCK, &name);
            }
        }
        self.lifelong = None;
    }
}

/// A sysfs write of a few bytes: no I2C behind it, so it stays on the I/O
/// thread without a blocking pool.
fn write(path: &str, value: &str) -> bool {
    match std::fs::write(path, value) {
        Ok(()) => true,
        Err(e) => {
            log::warn("power", format_args!("{path}: {e}"));
            false
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::{battery_warning, is_background_wake, measurement, Battery, Value};

    #[test]
    fn each_battery_threshold_warns_once_on_the_way_down() {
        let mut warned_at = 100;
        let mut titles = Vec::new();
        for level in (1..=25).rev() {
            if let Some(w) = super::battery_warning(level, 1, warned_at, "PowerOff") {
                warned_at = w.at;
                titles.push(w.title);
            }
        }
        assert_eq!(titles, ["Battery Low", "Low Battery", "Very Low Battery"]);
        let critical = super::battery_warning(2, 4, warned_at, "PowerOff").map(|w| w.body);
        assert_eq!(
            critical.as_deref(),
            Some("Device will turn off in 10 seconds to prevent data loss")
        );
        assert!(super::battery_warning(2, 4, 2, "PowerOff").is_none());
    }
    use std::io::Write;

    const ARMED: i64 = 1_792_236_376;

    struct Marker(tempfile::NamedTempFile);

    impl Marker {
        fn as_str(&self) -> &str {
            self.0.path().to_str().unwrap_or_default()
        }
    }

    fn marker(contents: &str) -> Marker {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        file.write_all(contents.as_bytes()).unwrap();
        Marker(file)
    }

    #[test]
    fn a_wake_near_the_armed_time_is_background_work() {
        let m = marker(&ARMED.to_string());
        assert!(is_background_wake(m.as_str(), 0, ARMED));
        assert!(is_background_wake(m.as_str(), 0, ARMED - 10));
        assert!(is_background_wake(m.as_str(), 0, ARMED + 60));
        assert!(!is_background_wake(m.as_str(), 0, ARMED - 11));
        assert!(!is_background_wake(m.as_str(), 0, ARMED + 61));
    }

    #[test]
    fn the_alarm_wins_over_background_work() {
        let m = marker(&ARMED.to_string());
        assert!(!is_background_wake(m.as_str(), ARMED, ARMED));
        assert!(!is_background_wake(m.as_str(), ARMED, ARMED + 60));
        assert!(!is_background_wake(m.as_str(), ARMED + 5, ARMED));
        assert!(is_background_wake(m.as_str(), ARMED + 3600, ARMED));
    }

    #[test]
    fn no_marker_or_a_bad_one_is_not_background_work() {
        assert!(!is_background_wake("/nonexistent/marathon-wake", 0, 0));
        assert!(!is_background_wake(marker("soon").as_str(), 0, 0));
        assert!(!is_background_wake(marker("").as_str(), 0, 0));
    }

    #[test]
    fn the_battery_reads_as_upower_states() {
        let charging = Battery {
            percentage: Some(54.6),
            percentage_available: true,
            state: 1,
            warning: 1,
            time_to_empty: 0,
            time_to_full: 1800,
        };
        assert_eq!(charging.level(), 55);
        assert!(charging.is_charging() && charging.is_plugged_in());
        assert_eq!(charging.estimated_minutes(), 30);
        let full = Battery {
            state: 4,
            ..charging
        };
        assert!(!full.is_charging() && full.is_plugged_in());
        assert_eq!(full.estimated_minutes(), -1);
        let draining = Battery {
            state: 2,
            time_to_empty: 7200,
            ..charging
        };
        assert!(!draining.is_plugged_in());
        assert_eq!(draining.estimated_minutes(), 120);
    }
    #[test]
    fn invalidated_percentage_disarms_until_a_fresh_measurement() {
        let mut battery = Battery {
            percentage: Some(0.0),
            percentage_available: true,
            state: 2,
            warning: 4,
            time_to_empty: 600,
            ..Battery::default()
        };
        assert!(measurement::can_arm_shutdown(
            battery.level(),
            battery.warning,
            false
        ));
        battery.invalidate("Percentage");
        assert_eq!(battery.level(), -1);
        assert_eq!(battery.estimated_minutes(), -1);
        assert!(!measurement::can_arm_shutdown(
            battery.level(),
            battery.warning,
            false
        ));
        for percentage in [0.0, 100.0] {
            battery.set("Percentage", &Value::from(percentage));
            assert_eq!(battery.level(), if percentage == 0.0 { 0 } else { 100 });
        }
        battery.percentage_available = false;
        assert_eq!(battery.level(), -1);
    }

    #[test]
    fn invalidated_times_do_not_reappear_after_state_changes() {
        let mut battery = Battery {
            percentage: Some(50.0),
            percentage_available: true,
            state: 2,
            time_to_empty: 3600,
            time_to_full: 1800,
            ..Battery::default()
        };
        assert_eq!(battery.estimated_minutes(), 60);
        battery.invalidate("TimeToEmpty");
        assert_eq!(battery.estimated_minutes(), -1);
        battery.state = 1;
        assert_eq!(battery.estimated_minutes(), 30);
        battery.invalidate("TimeToFull");
        assert_eq!(battery.estimated_minutes(), -1);
        battery.state = 2;
        assert_eq!(battery.estimated_minutes(), -1);
        battery.set("TimeToEmpty", &Value::from(120_i64));
        assert_eq!(battery.estimated_minutes(), 2);
        assert_eq!(battery.level(), 50);
    }

    #[test]
    fn invalidated_state_and_warning_clear_cached_decisions() {
        let mut battery = Battery {
            percentage: Some(50.0),
            percentage_available: true,
            state: 1,
            warning: 4,
            time_to_full: 1800,
            ..Battery::default()
        };
        battery.invalidate("UnrelatedProperty");
        assert_eq!(battery.level(), 50);
        assert!(battery.is_charging());
        battery.invalidate("State");
        battery.invalidate("WarningLevel");
        assert!(!battery.is_charging());
        assert!(!battery.is_plugged_in());
        assert_eq!(battery.estimated_minutes(), -1);
        assert_eq!(battery.warning, 0);
        assert!(!measurement::can_arm_shutdown(
            battery.level(),
            battery.warning,
            false
        ));
    }

    #[test]
    fn unknown_percentage_never_warns_even_at_upower_critical() {
        for warning in 0..=10 {
            assert!(battery_warning(-1, warning, 100, "PowerOff").is_none());
        }
    }
}

static POWER: OnceLock<cxx_qt::CxxQtThread<Power>> = OnceLock::new();
// ScheduleWake calls, answered once systemd has their timer.
static WAKES: LazyLock<Mutex<HashMap<String, Vec<Sender<bool>>>>> = LazyLock::new(Mutex::default);

fn state(power: &Power) -> State {
    State::from([
        ("dozing".to_owned(), value(!display::screen_on())),
        ("batteryLevel".to_owned(), value(power.battery_level)),
        ("isCharging".to_owned(), value(power.is_charging)),
        ("isPluggedIn".to_owned(), value(power.is_plugged_in)),
        (
            "isPowerSaveMode".to_owned(),
            value(power.is_power_save_mode),
        ),
        (
            "estimatedBatteryTime".to_owned(),
            value(power.estimated_battery_time),
        ),
        (
            "powerProfile".to_owned(),
            value(power.power_profile.to_string()),
        ),
        (
            "powerProfilesSupported".to_owned(),
            value(power.power_profiles_supported),
        ),
    ])
}

/// Holds `name` awake for `time`, from another of the shell's Rust objects.
pub(crate) fn hold_wakelock(name: &'static str, time: std::time::Duration) {
    let Some(qt) = POWER.get().cloned() else {
        return;
    };
    qt.queue(move |obj| {
        obj.acquire_wakelock(&QString::from(name));
    })
    .ok();
    io::spawn(async move {
        async_io::Timer::after(time).await;
        qt.queue(move |obj| {
            obj.release_wakelock(&QString::from(name));
        })
        .ok();
    });
}

/// Power1's state moved: the battery, the profile or the screen.
pub(crate) fn state_changed() {
    if let Some(qt) = POWER.get() {
        qt.queue(|obj| ipc::signal("Power", "StateChanged", (state(&obj),)))
            .ok();
    }
}

struct Power1 {
    qt: cxx_qt::CxxQtThread<Power>,
}

#[zbus::interface(name = "org.marathonos.Shell.Power1")]
impl Power1 {
    async fn get_state(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<State> {
        ipc::admit(&h, "Power", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| state(&obj)).await
    }

    async fn set_power_save_mode(
        &self,
        enabled: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Power", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_power_save_mode(enabled)).await
    }

    async fn set_power_profile(
        &self,
        profile: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Power", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_power_profile(&QString::from(&profile));
        })
        .await
    }

    async fn suspend(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Power", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.suspend()).await
    }

    async fn restart(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Power", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.restart()).await
    }

    async fn shutdown(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Power", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.shutdown()).await
    }

    /// Turns the screen on as an alarm, call or notification does.
    async fn wake(&self, reason: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        let caller = ipc::admit(&h, "Power", &["system"]).await?;
        if !["alarm", "call", "notification"].contains(&reason.as_str()) {
            return Err(fdo::Error::InvalidArgs("Unknown wake reason".into()));
        }
        log::warn(
            "power",
            format_args!("{caller} wakes the screen for {reason}"),
        );
        let display = display::DISPLAY
            .get()
            .ok_or_else(|| fdo::Error::Failed("no display".into()))?;
        ipc::on_gui(display, display::qobject::Display::turn_screen_on).await?;
        Ok(true)
    }

    /// Has a suspended device resume at `epoch_secs`, in Doze as for
    /// background work; one per app, replacing the last.
    async fn schedule_wake(
        &self,
        epoch_secs: i64,
        reason: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<bool> {
        let caller = ipc::admit(&h, "Power", &["system"]).await?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX));
        if epoch_secs <= now {
            return Err(fdo::Error::InvalidArgs(
                "Wake time is not in the future".into(),
            ));
        }
        log::warn(
            "power",
            format_args!("{caller} schedules a wake-up at {epoch_secs} for {reason}"),
        );
        let key = format!("app-{caller}");
        let (tx, rx) = async_channel::bounded(1);
        WAKES
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .entry(key.clone())
            .or_default()
            .push(tx);
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_wake_timer(&QString::from(&key), epoch_secs);
        })
        .await?;
        Ok(rx.recv().await.unwrap_or(false))
    }
}
