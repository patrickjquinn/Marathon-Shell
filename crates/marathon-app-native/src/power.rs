//! `Power`: the shell's Power1 for system apps.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QDateTime, QString};

use crate::shell::{get, mirror, Service, Update};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qdatetime.h");
        type QDateTime = cxx_qt_lib::QDateTime;
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
        /// False once the shell refuses the system permission.
        #[qproperty(bool, permitted, READ, NOTIFY = state_changed)]
        type Power = super::PowerRust;

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

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct PowerRust {
    battery_level: i32,
    is_charging: bool,
    is_plugged_in: bool,
    is_power_save_mode: bool,
    estimated_battery_time: i32,
    power_profile: QString,
    power_profiles_supported: bool,
    permitted: bool,
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
                    p.battery_level = get(&s, "batteryLevel");
                    p.is_charging = get(&s, "isCharging");
                    p.is_plugged_in = get(&s, "isPluggedIn");
                    p.is_power_save_mode = get(&s, "isPowerSaveMode");
                    p.estimated_battery_time = get(&s, "estimatedBatteryTime");
                    p.power_profile = get(&s, "powerProfile");
                    p.power_profiles_supported = get(&s, "powerProfilesSupported");
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

    fn schedule_wake(&self, when: &QDateTime, reason: &QString) -> bool {
        let at = when.to_msecs_since_epoch() / 1000;
        POWER.ask_now("ScheduleWake", &(at, reason.to_string())).unwrap_or(false)
    }
}
