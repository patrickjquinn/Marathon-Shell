//! `Display`: the shell's Display1 for system apps.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::shell::{get, mirror, Service, Update};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY = state_changed)]
        #[qproperty(bool, auto_brightness_enabled, cxx_name = "autoBrightnessEnabled", READ, WRITE = set_auto_brightness_enabled, NOTIFY = state_changed)]
        #[qproperty(bool, rotation_locked, cxx_name = "rotationLocked", READ, WRITE = set_rotation_locked, NOTIFY = state_changed)]
        #[qproperty(bool, rotation_available, cxx_name = "rotationAvailable", READ, NOTIFY = state_changed)]
        #[qproperty(bool, light_sensor_available, cxx_name = "lightSensorAvailable", READ, NOTIFY = state_changed)]
        #[qproperty(bool, torch_available, cxx_name = "torchAvailable", READ, NOTIFY = state_changed)]
        #[qproperty(f64, brightness, READ, WRITE = set_brightness, NOTIFY = state_changed)]
        #[qproperty(bool, night_light_enabled, cxx_name = "nightLightEnabled", READ, WRITE = set_night_light_enabled, NOTIFY = state_changed)]
        #[qproperty(i32, night_light_temperature, cxx_name = "nightLightTemperature", READ, WRITE = set_night_light_temperature, NOTIFY = state_changed)]
        #[qproperty(QString, night_light_schedule, cxx_name = "nightLightSchedule", READ, WRITE = set_night_light_schedule, NOTIFY = state_changed)]
        /// False once the shell refuses the system permission.
        #[qproperty(bool, permitted, READ, NOTIFY = state_changed)]
        type Display = super::DisplayRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);

        #[cxx_name = "setAutoBrightnessEnabled"]
        fn set_auto_brightness_enabled(self: Pin<&mut Display>, enabled: bool);
        #[cxx_name = "setRotationLocked"]
        fn set_rotation_locked(self: Pin<&mut Display>, locked: bool);
        #[cxx_name = "setBrightness"]
        fn set_brightness(self: Pin<&mut Display>, brightness: f64);
        #[cxx_name = "setNightLightEnabled"]
        fn set_night_light_enabled(self: Pin<&mut Display>, enabled: bool);
        #[cxx_name = "setNightLightTemperature"]
        fn set_night_light_temperature(self: Pin<&mut Display>, temperature: i32);
        #[cxx_name = "setNightLightSchedule"]
        fn set_night_light_schedule(self: Pin<&mut Display>, schedule: &QString);
        #[qinvokable]
        #[cxx_name = "setScreenState"]
        fn set_screen_state(self: &Display, on: bool);
    }

    impl cxx_qt::Threading for Display {}
    impl cxx_qt::Initialize for Display {}
}

use qobject::Display;

const DISPLAY: Service = Service("Display");

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct DisplayRust {
    available: bool,
    auto_brightness_enabled: bool,
    rotation_locked: bool,
    rotation_available: bool,
    light_sensor_available: bool,
    torch_available: bool,
    brightness: f64,
    night_light_enabled: bool,
    night_light_temperature: i32,
    night_light_schedule: QString,
    permitted: bool,
}

impl cxx_qt::Initialize for Display {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().permitted = true;
        mirror(self.qt_thread(), DISPLAY, "system", |mut obj, update| {
            let mut d = obj.as_mut().rust_mut();
            match update {
                Update::Refused => d.permitted = false,
                Update::State(s) => {
                    d.permitted = true;
                    d.available = get(&s, "available");
                    d.auto_brightness_enabled = get(&s, "autoBrightnessEnabled");
                    d.rotation_locked = get(&s, "rotationLocked");
                    d.rotation_available = get(&s, "rotationAvailable");
                    d.light_sensor_available = get(&s, "lightSensorAvailable");
                    d.torch_available = get(&s, "torchAvailable");
                    d.brightness = get(&s, "brightness");
                    d.night_light_enabled = get(&s, "nightLightEnabled");
                    d.night_light_temperature = get(&s, "nightLightTemperature");
                    d.night_light_schedule = get(&s, "nightLightSchedule");
                }
            }
            obj.state_changed();
        });
    }
}

impl Display {
    crate::shell::calls! { DISPLAY;
        set_screen_state(on: bool) => "SetScreenState";
    }
    crate::shell::calls! { DISPLAY; mut
        set_auto_brightness_enabled(enabled: bool) => "SetAutoBrightness";
        set_rotation_locked(locked: bool) => "SetRotationLock";
        set_brightness(brightness: f64) => "SetBrightness";
        set_night_light_enabled(enabled: bool) => "SetNightLightEnabled";
        set_night_light_temperature(temperature: i32) => "SetNightLightTemperature";
        set_night_light_schedule(schedule: &QString) => "SetNightLightSchedule";
    }
}
