//! `SystemStatusStore` and `SystemControlStore`: the status bar's and quick
//! controls' view of the shell, for apps that draw their own. They read
//! only what the app already holds; they never ask for a permission.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use zbus::zvariant::OwnedValue;

use crate::shell::{get, relay, watch, Field, Service, Update};
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(i32, battery_level, cxx_name = "batteryLevel", READ, NOTIFY)]
        #[qproperty(bool, wifi_connected, cxx_name = "wifiConnected", READ, NOTIFY)]
        #[qproperty(QString, wifi_network, cxx_name = "wifiNetwork", READ, NOTIFY)]
        type SystemStatusStore = super::SystemStatusStoreRust;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, is_wifi_on, cxx_name = "isWifiOn", READ, NOTIFY)]
        #[qproperty(bool, is_bluetooth_on, cxx_name = "isBluetoothOn", READ, NOTIFY)]
        #[qproperty(bool, is_airplane_mode_on, cxx_name = "isAirplaneModeOn", READ, NOTIFY)]
        #[qproperty(bool, is_rotation_locked, cxx_name = "isRotationLocked", READ, NOTIFY)]
        #[qproperty(bool, is_dnd_mode, cxx_name = "isDndMode", READ, NOTIFY)]
        #[qproperty(i32, brightness, READ, NOTIFY)]
        #[qproperty(i32, volume, READ, NOTIFY)]
        type SystemControlStore = super::SystemControlStoreRust;

        #[qinvokable]
        #[cxx_name = "toggleWifi"]
        fn toggle_wifi(self: &SystemControlStore);
        #[qinvokable]
        #[cxx_name = "toggleBluetooth"]
        fn toggle_bluetooth(self: &SystemControlStore);
        #[qinvokable]
        #[cxx_name = "toggleAirplaneMode"]
        fn toggle_airplane_mode(self: &SystemControlStore);
        #[qinvokable]
        #[cxx_name = "toggleRotationLock"]
        fn toggle_rotation_lock(self: &SystemControlStore);
        #[qinvokable]
        #[cxx_name = "toggleDndMode"]
        fn toggle_dnd_mode(self: &SystemControlStore);
        /// 0 to 100.
        #[qinvokable]
        #[cxx_name = "setBrightness"]
        fn set_brightness(self: Pin<&mut SystemControlStore>, value: i32);
        /// 0 to 100.
        #[qinvokable]
        #[cxx_name = "setVolume"]
        fn set_volume(self: Pin<&mut SystemControlStore>, value: i32);
    }

    impl cxx_qt::Threading for SystemStatusStore {}
    impl cxx_qt::Initialize for SystemStatusStore {}
    impl cxx_qt::Threading for SystemControlStore {}
    impl cxx_qt::Initialize for SystemControlStore {}
}

use qobject::{SystemControlStore, SystemStatusStore};

const POWER: Service = Service::shell("Power");
const NETWORK: Service = Service::shell("Network");
const BLUETOOTH: Service = Service::shell("Bluetooth");
const DISPLAY: Service = Service::shell("Display");
const SETTINGS: Service = Service::session("Settings");
const AUDIO: Service = Service::session("Audio");

#[derive(Default)]
pub struct SystemStatusStoreRust {
    battery_level: i32,
    wifi_connected: bool,
    wifi_network: QString,
}

impl cxx_qt::Initialize for SystemStatusStore {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        watch(qt.clone(), POWER, "system", |mut obj, update| {
            if let Update::State(s) = update {
                set!(obj, battery_level, battery_level_changed, get(&s, "batteryLevel"));
            }
        });
        watch(qt, NETWORK, "network", |mut obj, update| {
            if let Update::State(s) = update {
                set!(obj, wifi_connected, wifi_connected_changed, get(&s, "wifiConnected"));
                set!(obj, wifi_network, wifi_network_changed, get(&s, "wifiSsid"));
            }
        });
    }
}

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct SystemControlStoreRust {
    is_wifi_on: bool,
    is_bluetooth_on: bool,
    is_airplane_mode_on: bool,
    is_rotation_locked: bool,
    is_dnd_mode: bool,
    brightness: i32,
    volume: i32,
}

impl Default for SystemControlStoreRust {
    fn default() -> Self {
        Self {
            is_wifi_on: true,
            is_bluetooth_on: false,
            is_airplane_mode_on: false,
            is_rotation_locked: false,
            is_dnd_mode: false,
            brightness: 50,
            volume: 50,
        }
    }
}

/// A 0 to 1 level as a percentage.
#[allow(clippy::cast_possible_truncation, reason = "0 to 100")]
fn percent(level: f64) -> i32 {
    (level.clamp(0.0, 1.0) * 100.0).round() as i32
}

impl cxx_qt::Initialize for SystemControlStore {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        watch(qt.clone(), NETWORK, "network", |mut obj, update| {
            if let Update::State(s) = update {
                set!(obj, is_wifi_on, is_wifi_on_changed, get(&s, "wifiEnabled"));
                set!(obj, is_airplane_mode_on, is_airplane_mode_on_changed, get(&s, "airplaneModeEnabled"));
            }
        });
        watch(qt.clone(), BLUETOOTH, "system", |mut obj, update| {
            if let Update::State(s) = update {
                set!(obj, is_bluetooth_on, is_bluetooth_on_changed, get(&s, "enabled"));
            }
        });
        watch(qt.clone(), DISPLAY, "system", |mut obj, update| {
            if let Update::State(s) = update {
                set!(obj, is_rotation_locked, is_rotation_locked_changed, get(&s, "rotationLocked"));
                set!(obj, brightness, brightness_changed, percent(get(&s, "brightness")));
            }
        });
        watch(qt.clone(), AUDIO, "system", |mut obj, update| {
            if let Update::State(s) = update {
                set!(obj, volume, volume_changed, percent(get(&s, "volume")));
            }
        });
        relay(qt.clone(), SETTINGS, "PropertyChanged", |obj, (name, value): (String, OwnedValue)| {
            if name == "dndEnabled" {
                show_dnd(obj, &value);
            }
        });
        io::spawn(async move {
            if let Ok(state) = SETTINGS.ask::<_, crate::shell::State>("GetState", &()).await {
                if let Some(dnd) = state.get("dndEnabled").cloned() {
                    qt.queue(move |obj| show_dnd(obj, &dnd)).ok();
                }
            }
        });
    }
}

fn show_dnd(mut obj: Pin<&mut SystemControlStore>, value: &OwnedValue) {
    if let Some(dnd) = bool::from_value(value) {
        set!(obj, is_dnd_mode, is_dnd_mode_changed, dnd);
    }
}

impl SystemControlStore {
    fn toggle_wifi(&self) {
        NETWORK.call("ToggleWifi", ());
    }

    fn toggle_bluetooth(&self) {
        BLUETOOTH.call("SetEnabled", (!self.is_bluetooth_on,));
    }

    fn toggle_airplane_mode(&self) {
        NETWORK.call("SetAirplaneMode", (!self.is_airplane_mode_on,));
    }

    fn toggle_rotation_lock(&self) {
        DISPLAY.call("SetRotationLock", (!self.is_rotation_locked,));
    }

    fn toggle_dnd_mode(&self) {
        let on = !self.is_dnd_mode;
        SETTINGS.call("SetProperty", ("dndEnabled", zbus::zvariant::Value::from(on)));
        AUDIO.call("SetDoNotDisturb", (on,));
    }

    fn set_brightness(mut self: Pin<&mut Self>, value: i32) {
        let value = value.clamp(0, 100);
        DISPLAY.call("SetBrightness", (f64::from(value) / 100.0,));
        set!(self, brightness, brightness_changed, value);
    }

    fn set_volume(mut self: Pin<&mut Self>, value: i32) {
        let value = value.clamp(0, 100);
        AUDIO.call("SetVolume", (f64::from(value) / 100.0,));
        set!(self, volume, volume_changed, value);
    }
}
