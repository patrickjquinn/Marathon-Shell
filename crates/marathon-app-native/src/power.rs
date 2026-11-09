//! `Power`: the shell's Power1 for system apps.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QDateTime, QList, QString};
use marathon_rt::io;

use crate::shell::{get, mirror, Field, Service, Update};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qdatetime.h");
        type QDateTime = cxx_qt_lib::QDateTime;
        include!("cxx-qt-lib/qlist.h");
        type QList_f64 = cxx_qt_lib::QList<f64>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(i32, battery_level, cxx_name = "batteryLevel", READ, NOTIFY = state_changed)]
        #[qproperty(bool, is_charging, cxx_name = "isCharging", READ, NOTIFY = state_changed)]
        #[qproperty(bool, is_plugged_in, cxx_name = "isPluggedIn", READ, NOTIFY = state_changed)]
        #[qproperty(bool, is_power_save_mode, cxx_name = "isPowerSaveMode", READ, NOTIFY = state_changed)]
        #[qproperty(i32, estimated_battery_time, cxx_name = "estimatedBatteryTime", READ, NOTIFY = state_changed)]
        #[qproperty(QString, power_profile, cxx_name = "powerProfile", READ, NOTIFY = state_changed)]
        #[qproperty(bool, power_profiles_supported, cxx_name = "powerProfilesSupported", READ, NOTIFY = state_changed)]
        /// The phone has an assistant key (the key between the volume keys).
        #[qproperty(bool, has_assist_key, cxx_name = "hasAssistKey", READ, NOTIFY = state_changed)]
        /// The keyboard has a trackpad.
        #[qproperty(bool, has_trackpad, cxx_name = "hasTrackpad", READ, NOTIFY = state_changed)]
        /// False once the shell refuses the system permission.
        #[qproperty(bool, permitted, READ, NOTIFY = state_changed)]
        /// UPower's battery history, oldest first: time (s since the epoch),
        /// charge (%) pairs; and time, power draw (W) pairs while discharging.
        #[qproperty(QList_f64, charge_history, cxx_name = "chargeHistory", READ, NOTIFY = history_changed)]
        #[qproperty(QList_f64, rate_history, cxx_name = "rateHistory", READ, NOTIFY = history_changed)]
        type Power = super::PowerRust;

        #[qsignal]
        #[cxx_name = "historyChanged"]
        fn history_changed(self: Pin<&mut Self>);
        /// Reads the last `hours` of history; historyChanged follows.
        #[qinvokable]
        #[cxx_name = "loadHistory"]
        fn load_history(self: &Power, hours: i32);

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "setPowerSaveMode"]
        fn set_power_save_mode(self: &Power, enabled: bool);
        #[qinvokable]
        #[cxx_name = "setPowerProfile"]
        fn set_power_profile(self: &Power, profile: &QString);
        #[qinvokable]
        fn suspend(self: &Power);
        #[qinvokable]
        fn restart(self: &Power);
        #[qinvokable]
        fn shutdown(self: &Power);
        /// Turns the screen on as an alarm, call or notification does.
        #[qinvokable]
        fn wake(self: &Power, reason: &QString) -> bool;
        /// Has a suspended device resume at `when`, in Doze.
        #[qinvokable]
        #[cxx_name = "scheduleWake"]
        fn schedule_wake(self: &Power, when: &QDateTime, reason: &QString) -> bool;
    }

    impl cxx_qt::Threading for Power {}

    impl cxx_qt::Initialize for Power {}
}

use qobject::Power;

const POWER: Service = Service::shell("Power");

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct PowerRust {
    battery_level: i32,
    is_charging: bool,
    is_plugged_in: bool,
    is_power_save_mode: bool,
    estimated_battery_time: i32,
    power_profile: QString,
    power_profiles_supported: bool,
    has_assist_key: bool,
    has_trackpad: bool,
    permitted: bool,
    charge_history: QList<f64>,
    rate_history: QList<f64>,
}

impl Default for PowerRust {
    fn default() -> Self {
        Self {
            battery_level: -1,
            is_charging: false,
            is_plugged_in: false,
            is_power_save_mode: false,
            estimated_battery_time: -1,
            power_profile: QString::default(),
            power_profiles_supported: false,
            has_assist_key: false,
            has_trackpad: false,
            permitted: false,
            charge_history: QList::default(),
            rate_history: QList::default(),
        }
    }
}

impl cxx_qt::Initialize for Power {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().permitted = true;
        mirror(self.qt_thread(), POWER, "system", |mut obj, update| {
            let mut p = obj.as_mut().rust_mut();
            match update {
                Update::Refused => p.permitted = false,
                Update::State(s) => {
                    p.permitted = true;
                    p.battery_level = s
                        .get("batteryLevel")
                        .and_then(i32::from_value)
                        .unwrap_or(-1);
                    p.is_charging = get(&s, "isCharging");
                    p.is_plugged_in = get(&s, "isPluggedIn");
                    p.is_power_save_mode = get(&s, "isPowerSaveMode");
                    p.estimated_battery_time = get(&s, "estimatedBatteryTime");
                    p.power_profile = get(&s, "powerProfile");
                    p.power_profiles_supported = get(&s, "powerProfilesSupported");
                    p.has_assist_key = get(&s, "hasAssistKey");
                    p.has_trackpad = get(&s, "hasTrackpad");
                }
            }
            obj.state_changed();
        });
    }
}

impl Power {
    crate::shell::calls! { POWER;
        set_power_save_mode(enabled: bool) => "SetPowerSaveMode";
        suspend() => "Suspend";
        restart() => "Restart";
        shutdown() => "Shutdown";
        set_power_profile(profile: &QString) => "SetPowerProfile";
    }
    crate::shell::asks! { POWER;
        wake(reason: &QString) -> bool => "Wake";
    }

    fn load_history(&self, hours: i32) {
        let qt = self.qt_thread();
        let span = u32::try_from(hours.clamp(1, 24 * 7)).unwrap_or(24) * 3600;
        io::spawn(async move {
            let (charge, rate) = upower_history(span).await.unwrap_or_default();
            qt.queue(move |mut obj| {
                let mut p = obj.as_mut().rust_mut();
                p.charge_history = qlist(&charge);
                p.rate_history = qlist(&rate);
                obj.history_changed();
            })
            .ok();
        });
    }

    fn schedule_wake(&self, when: &QDateTime, reason: &QString) -> bool {
        let at = when.to_msecs_since_epoch() / 1000;
        POWER
            .ask_now("ScheduleWake", &(at, reason.to_string()))
            .unwrap_or(false)
    }
}

/// The battery's charge and rate history as UPower keeps it (it samples on
/// its own; nothing here runs between reads), as flat time, value pairs.
async fn upower_history(span: u32) -> zbus::Result<(Vec<f64>, Vec<f64>)> {
    const UPOWER: &str = "org.freedesktop.UPower";
    let bus = io::system_bus().await?;
    let upower = zbus::Proxy::new(&bus, UPOWER, "/org/freedesktop/UPower", UPOWER).await?;
    let devices: Vec<zbus::OwnedObjectPath> = upower.call("EnumerateDevices", &()).await?;
    let Some(battery) = devices
        .into_iter()
        .find(|p| p.as_str().contains("/battery_"))
    else {
        return Ok(Default::default());
    };
    let device = zbus::Proxy::new(&bus, UPOWER, battery, "org.freedesktop.UPower.Device").await?;
    Ok((
        history(&device, "charge", span, false).await?,
        history(&device, "rate", span, true).await?,
    ))
}

/// `draining`: only what was read while the battery discharged (UPower state
/// 2). Samples in the unknown state (0) are dropped: UPower logs a 0 % one at boot.
async fn history(
    device: &zbus::Proxy<'_>,
    kind: &str,
    span: u32,
    draining: bool,
) -> zbus::Result<Vec<f64>> {
    let rows: Vec<(u32, f64, u32)> = device.call("GetHistory", &(kind, span, 240u32)).await?;
    Ok(rows
        .into_iter()
        .rev()
        .filter(|(_, _, state)| *state != 0 && (!draining || *state == 2))
        .flat_map(|(time, value, _)| [f64::from(time), value])
        .collect())
}

fn qlist(values: &[f64]) -> QList<f64> {
    let mut list = QList::default();
    for v in values {
        list.append(*v);
    }
    list
}
