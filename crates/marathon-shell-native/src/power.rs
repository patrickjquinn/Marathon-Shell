//! `PowerManagerService`: battery, power profiles, wakelocks, sleep and the
//! power actions. QML and the shell's C++ see the `QObject` `PowerManagerCpp`;
//! everything that talks to `UPower`, logind, power-profiles-daemon, systemd
//! or sysfs runs in one actor on the I/O thread.

use std::collections::{BTreeMap, BTreeSet};
use std::pin::Pin;
use std::time::{SystemTime, UNIX_EPOCH};

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QStringList};
use futures_lite::{stream, StreamExt};
use zbus::fdo::{DBusProxy, PropertiesProxy};
use zbus::names::InterfaceName;
use zbus::zvariant::{OwnedFd, OwnedValue, Value};

use crate::wake_timer::WakeTimer;
use crate::{io, log};

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
        #[qproperty(i32, battery_level, cxx_name = "batteryLevel", READ = battery_level, NOTIFY = battery_level_changed)]
        #[qproperty(u32, warning_level, cxx_name = "warningLevel", READ = warning_level, NOTIFY = warning_level_changed)]
        #[qproperty(bool, is_charging, cxx_name = "isCharging", READ = is_charging, NOTIFY = is_charging_changed)]
        #[qproperty(bool, is_plugged_in, cxx_name = "isPluggedIn", READ = is_plugged_in, NOTIFY = is_plugged_in_changed)]
        #[qproperty(bool, is_power_save_mode, cxx_name = "isPowerSaveMode", READ = is_power_save_mode, NOTIFY = is_power_save_mode_changed)]
        #[qproperty(i32, estimated_battery_time, cxx_name = "estimatedBatteryTime", READ = estimated_battery_time, NOTIFY = estimated_battery_time_changed)]
        #[qproperty(QString, power_profile, cxx_name = "powerProfile", READ = power_profile, NOTIFY = power_profile_changed)]
        #[qproperty(bool, power_profiles_supported, cxx_name = "powerProfilesSupported", READ = power_profiles_supported, NOTIFY = power_profile_changed)]
        #[qproperty(QStringList, active_wakelocks, cxx_name = "activeWakelocks", READ = active_wakelocks, NOTIFY = active_wakelocks_changed)]
        #[qproperty(i32, wake_lock_count, cxx_name = "wakeLockCount", READ = wake_lock_count, NOTIFY = active_wakelocks_changed)]
        #[qproperty(QString, critical_action, cxx_name = "criticalAction", READ = critical_action, NOTIFY = critical_action_changed)]
        type PowerManagerCpp = super::PowerRust;

        // Getters under the names the shell's C++ calls.
        #[cxx_name = "batteryLevel"]
        fn battery_level(self: &PowerManagerCpp) -> i32;
        #[cxx_name = "warningLevel"]
        fn warning_level(self: &PowerManagerCpp) -> u32;
        #[cxx_name = "isCharging"]
        fn is_charging(self: &PowerManagerCpp) -> bool;
        #[cxx_name = "isPluggedIn"]
        fn is_plugged_in(self: &PowerManagerCpp) -> bool;
        #[cxx_name = "isPowerSaveMode"]
        fn is_power_save_mode(self: &PowerManagerCpp) -> bool;
        #[cxx_name = "estimatedBatteryTime"]
        fn estimated_battery_time(self: &PowerManagerCpp) -> i32;
        #[cxx_name = "powerProfile"]
        fn power_profile(self: &PowerManagerCpp) -> QString;
        #[cxx_name = "powerProfilesSupported"]
        fn power_profiles_supported(self: &PowerManagerCpp) -> bool;
        #[cxx_name = "activeWakelocks"]
        fn active_wakelocks(self: &PowerManagerCpp) -> QStringList;
        #[cxx_name = "wakeLockCount"]
        fn wake_lock_count(self: &PowerManagerCpp) -> i32;
        #[cxx_name = "criticalAction"]
        fn critical_action(self: &PowerManagerCpp) -> QString;
        #[qsignal]
        #[cxx_name = "batteryLevelChanged"]
        fn battery_level_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "warningLevelChanged"]
        fn warning_level_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "isChargingChanged"]
        fn is_charging_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "isPluggedInChanged"]
        fn is_plugged_in_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "isPowerSaveModeChanged"]
        fn is_power_save_mode_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "estimatedBatteryTimeChanged"]
        fn estimated_battery_time_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "powerProfileChanged"]
        fn power_profile_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "activeWakelocksChanged"]
        fn active_wakelocks_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "criticalActionChanged"]
        fn critical_action_changed(self: Pin<&mut Self>);
        /// UPower's warning level reached critical (4) or beyond.
        #[qsignal]
        #[cxx_name = "criticalBattery"]
        fn critical_battery(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "powerError"]
        fn power_error(self: Pin<&mut Self>, message: &QString);
        /// The system woke; `background_wake` when marathon-background armed it.
        #[qsignal]
        #[cxx_name = "resumedFromSuspend"]
        fn resumed_from_suspend(self: Pin<&mut Self>, background_wake: bool);

        #[qinvokable]
        fn suspend(self: &PowerManagerCpp);
        #[qinvokable]
        fn hibernate(self: &PowerManagerCpp);
        #[qinvokable]
        #[cxx_name = "hybridSleep"]
        fn hybrid_sleep(self: &PowerManagerCpp);
        #[qinvokable]
        fn shutdown(self: &PowerManagerCpp);
        #[qinvokable]
        fn restart(self: &PowerManagerCpp);
        #[qinvokable]
        #[cxx_name = "setPowerSaveMode"]
        fn set_power_save_mode(self: Pin<&mut PowerManagerCpp>, enabled: bool);
        #[qinvokable]
        #[cxx_name = "setPowerProfile"]
        fn set_power_profile(self: &PowerManagerCpp, profile: &QString);
        #[qinvokable]
        #[cxx_name = "acquireWakelock"]
        fn acquire_wakelock(self: Pin<&mut PowerManagerCpp>, name: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "releaseWakelock"]
        fn release_wakelock(self: Pin<&mut PowerManagerCpp>, name: &QString) -> bool;
        /// Replaces the shell's own sleep delay lock with one for `who`.
        #[qinvokable]
        #[cxx_name = "inhibitSuspend"]
        fn inhibit_suspend(self: &PowerManagerCpp, who: &QString, why: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "releaseInhibitor"]
        fn release_inhibitor(self: &PowerManagerCpp);
        /// The next alarm, which wakes a suspended device; 0 for none.
        #[qinvokable]
        #[cxx_name = "setAlarmWake"]
        fn set_alarm_wake(self: &PowerManagerCpp, epoch_secs: i64);
    }

    impl cxx_qt::Threading for PowerManagerCpp {}
    impl cxx_qt::Initialize for PowerManagerCpp {}
}

use qobject::PowerManagerCpp;

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
    held: BTreeSet<String>,
    actor: Option<Sender<Command>>,
}

impl Default for PowerRust {
    fn default() -> Self {
        Self {
            battery_level: 100,
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
    AlarmWake(i64),
}

#[derive(Clone, Copy)]
enum Action {
    Suspend,
    Hibernate,
    HybridSleep,
    PowerOff,
    Reboot,
}

impl cxx_qt::Initialize for PowerManagerCpp {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(64);
        let qt = self.qt_thread();
        io::spawn(run(qt, rx));
        self.as_mut().rust_mut().actor = Some(tx);
    }
}

impl PowerManagerCpp {
    fn battery_level(&self) -> i32 {
        self.battery_level
    }

    fn warning_level(&self) -> u32 {
        self.warning_level
    }

    fn is_charging(&self) -> bool {
        self.is_charging
    }

    fn is_plugged_in(&self) -> bool {
        self.is_plugged_in
    }

    fn is_power_save_mode(&self) -> bool {
        self.is_power_save_mode
    }

    fn estimated_battery_time(&self) -> i32 {
        self.estimated_battery_time
    }

    fn power_profile(&self) -> QString {
        self.power_profile.clone()
    }

    fn power_profiles_supported(&self) -> bool {
        self.power_profiles_supported
    }

    fn active_wakelocks(&self) -> QStringList {
        self.active_wakelocks.clone()
    }

    fn wake_lock_count(&self) -> i32 {
        self.wake_lock_count
    }

    fn critical_action(&self) -> QString {
        self.critical_action.clone()
    }

    fn send(&self, command: Command) -> bool {
        self.actor.as_ref().is_some_and(|a| a.try_send(command).is_ok())
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
            self.as_mut().rust_mut().profile_before_saver.take().unwrap_or_else(|| "balanced".to_owned())
        };
        self.request_profile(&profile);
        self.as_mut().rust_mut().is_power_save_mode = enabled;
        self.is_power_save_mode_changed();
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
            return log::warn("power", format_args!("no power profile service; cannot set {name}"));
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
        self.active_wakelocks_changed();
    }

    fn inhibit_suspend(&self, who: &QString, why: &QString) -> bool {
        self.send(Command::Inhibit(who.to_string(), why.to_string()))
    }

    fn release_inhibitor(&self) {
        self.send(Command::ReleaseInhibitor);
    }

    fn set_alarm_wake(&self, epoch_secs: i64) {
        self.send(Command::AlarmWake(epoch_secs));
    }

    fn apply_battery(mut self: Pin<&mut Self>, battery: Battery) {
        let level = battery.level();
        if self.battery_level != level {
            self.as_mut().rust_mut().battery_level = level;
            self.as_mut().battery_level_changed();
        }
        if self.warning_level != battery.warning {
            self.as_mut().rust_mut().warning_level = battery.warning;
            self.as_mut().warning_level_changed();
            if battery.warning >= 4 {
                self.as_mut().critical_battery();
            }
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
    }

    fn apply_profile(mut self: Pin<&mut Self>, profile: &str) {
        if !self.power_profiles_supported || self.power_profile.to_string() != profile {
            let mut rust = self.as_mut().rust_mut();
            rust.power_profiles_supported = true;
            rust.power_profile = QString::from(profile);
            self.as_mut().power_profile_changed();
        }
        let saver = profile == "power-saver";
        if self.is_power_save_mode != saver {
            self.as_mut().rust_mut().is_power_save_mode = saver;
            self.as_mut().is_power_save_mode_changed();
        }
    }

    fn apply_critical_action(mut self: Pin<&mut Self>, action: &str) {
        if self.critical_action.to_string() != action {
            self.as_mut().rust_mut().critical_action = QString::from(action);
            self.critical_action_changed();
        }
    }
}

/// `UPower`'s `DisplayDevice`, as its properties last said.
#[derive(Clone, Copy, Default)]
struct Battery {
    percentage: f64,
    state: u32,
    warning: u32,
    time_to_empty: i64,
    time_to_full: i64,
}

impl Battery {
    // UPower's states: 1 charging, 2 discharging, 4 fully charged,
    // 5 pending charge, 6 pending discharge.
    fn level(self) -> i32 {
        // A percentage is 0 to 100, so the cast cannot truncate.
        #[allow(clippy::cast_possible_truncation, reason = "a percentage, 0 to 100")]
        let level = self.percentage.round().clamp(0.0, 100.0) as i32;
        level
    }

    fn is_charging(self) -> bool {
        matches!(self.state, 1 | 5)
    }

    fn is_plugged_in(self) -> bool {
        matches!(self.state, 1 | 4 | 5)
    }

    fn estimated_minutes(self) -> i32 {
        let seconds = match self.state {
            2 | 6 => self.time_to_empty,
            1 | 5 => self.time_to_full,
            _ => 0,
        };
        if seconds > 0 { i32::try_from(seconds / 60).unwrap_or(i32::MAX) } else { -1 }
    }

    fn set(&mut self, name: &str, value: &Value<'_>) {
        match name {
            "Percentage" => self.percentage = value.downcast_ref().unwrap_or(self.percentage),
            "State" => self.state = value.downcast_ref().unwrap_or(self.state),
            "WarningLevel" => self.warning = value.downcast_ref().unwrap_or(self.warning),
            "TimeToEmpty" => self.time_to_empty = value.downcast_ref().unwrap_or(self.time_to_empty),
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
    std::fs::read_to_string(marker)
        .ok()
        .and_then(|s| s.trim().parse::<i64>().ok())
        .is_some_and(woke_for)
}

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait Logind {
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

type Qt = cxx_qt::CxxQtThread<PowerManagerCpp>;

enum Event {
    Command(Command),
    Closed,
    Sleep(bool),
    Battery(Vec<(String, OwnedValue)>),
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
    alarm_timer: WakeTimer,
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
        kernel_wakelocks: std::fs::OpenOptions::new().write(true).open(WAKE_LOCK).is_ok(),
        battery: Battery::default(),
        alarm: 0,
        alarm_timer: WakeTimer::new("alarm"),
    };
    actor.lifelong = actor.inhibit("marathon-shell", "Handle wake events").await;
    actor.read_critical_action(&qt).await;
    actor.read_battery(&qt).await;
    actor.read_profile(&qt).await;

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
            Event::Battery(changed) => {
                for (name, value) in &changed {
                    actor.battery.set(name, value);
                }
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
            Command::AlarmWake(epoch_secs) => {
                self.alarm = epoch_secs;
                match io::session_bus().await {
                    Ok(session) => self.alarm_timer.set(&session, epoch_secs).await,
                    Err(e) => log::warn("power", format_args!("no session bus: {e}")),
                }
            }
        }
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
        self.inhibit("Marathon Shell", &format!("Wakelock: {name}")).await
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
            qt.queue(move |obj| obj.power_error(&QString::from(message.as_str()))).ok();
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
        qt.queue(move |obj| obj.resumed_from_suspend(background)).ok();
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
        let Ok(upower) = UPowerProxy::new(&self.bus).await else { return };
        match upower.get_critical_action().await {
            Ok(action) if !action.is_empty() => {
                qt.queue(move |obj| obj.apply_critical_action(&action)).ok();
            }
            Ok(_) => {}
            Err(e) => log::warn("power", format_args!("no UPower critical action: {e}")),
        }
    }

    async fn properties(&self, service: &'static str, path: &'static str) -> Option<PropertiesProxy<'static>> {
        let built = PropertiesProxy::builder(&self.bus)
            .destination(service)
            .and_then(|b| b.path(path))
            .map(|b| b.cache_properties(zbus::proxy::CacheProperties::No));
        match built {
            Ok(b) => b.build().await.ok(),
            Err(e) => {
                log::warn("power", e);
                None
            }
        }
    }

    // A host without a battery reads as plugged in at 100%.
    async fn read_battery(&mut self, qt: &Qt) {
        let Some(props) = self.properties(UPOWER, DISPLAY_DEVICE).await else { return };
        let Ok(device) = InterfaceName::try_from(DEVICE) else { return };
        match props.get_all(device).await {
            Ok(all) => {
                for (name, value) in &all {
                    self.battery.set(name, value);
                }
                let battery = self.battery;
                qt.queue(move |obj| obj.apply_battery(battery)).ok();
            }
            Err(e) => log::warn("power", format_args!("no battery: {e}")),
        }
    }

    async fn read_profile(&self, qt: &Qt) {
        let Some(props) = self.properties(PROFILES, PROFILES_PATH).await else { return };
        let Ok(interface) = InterfaceName::try_from(PROFILES) else { return };
        if let Ok(value) = props.get(interface, "ActiveProfile").await {
            if let Ok(profile) = String::try_from(value) {
                queue_profile(qt, profile);
            }
        }
    }

    async fn set_profile(&self, qt: &Qt, name: String) {
        let Some(props) = self.properties(PROFILES, PROFILES_PATH).await else { return };
        let Ok(interface) = InterfaceName::try_from(PROFILES) else { return };
        // A profile switch runs the daemon's tuning; the I/O thread waits, not the GUI.
        match props.set(interface, "ActiveProfile", Value::from(name.as_str())).await {
            Ok(()) => queue_profile(qt, name),
            Err(e) => log::warn("power", format_args!("power profile {name} refused: {e}")),
        }
    }

    async fn sleep_events(&self) -> stream::Boxed<Event> {
        match self.logind.receive_prepare_for_sleep().await {
            Ok(s) => s.filter_map(|signal| signal.args().ok().map(|a| Event::Sleep(a.start))).boxed(),
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
                    let changed = args
                        .changed_properties()
                        .iter()
                        .filter_map(|(k, v)| Some(((*k).to_owned(), v.try_to_owned().ok()?)))
                        .collect();
                    Some(Event::Battery(changed))
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
                        Some(Event::Profile(Some(String::try_from(profile.try_to_owned().ok()?).ok()?)))
                    })
                    .boxed(),
                Err(_) => stream::empty().boxed(),
            },
            None => stream::empty().boxed(),
        };
        let appeared = match DBusProxy::new(&self.bus).await {
            Ok(dbus) => match dbus.receive_name_owner_changed_with_args(&[(0, PROFILES)]).await {
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
    use super::{is_background_wake, Battery};
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
        let charging = Battery { percentage: 54.6, state: 1, warning: 1, time_to_empty: 0, time_to_full: 1800 };
        assert_eq!(charging.level(), 55);
        assert!(charging.is_charging() && charging.is_plugged_in());
        assert_eq!(charging.estimated_minutes(), 30);
        let full = Battery { state: 4, ..charging };
        assert!(!full.is_charging() && full.is_plugged_in());
        assert_eq!(full.estimated_minutes(), -1);
        let draining = Battery { state: 2, time_to_empty: 7200, ..charging };
        assert!(!draining.is_plugged_in());
        assert_eq!(draining.estimated_minutes(), 120);
    }
}
