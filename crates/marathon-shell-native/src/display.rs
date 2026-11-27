//! The display: the backlight and the adaptive curve that sets it, whether
//! the screen is on, and the ambient light and proximity sensors. Sysfs I/O
//! runs on the I/O thread: a DCS or I2C backlight can take milliseconds a
//! write, and a vcnl4000-class sensor measures while its read waits. The one
//! exception is the doze blank, which must land before the CRTC goes off.
//! The orientation comes from iio-sensor-proxy, claimed only while the screen
//! is on, rotation is unlocked and an app, the one thing that turns, is in
//! the foreground.

use std::collections::VecDeque;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::{future, StreamExt};
use zbus::fdo;
use zbus::message::Header;

use crate::io::{self, read};
use crate::ipc::{self, value, State};
use crate::night_light::{self, Plan, Schedule};
use crate::{eink, flashlight, log};
use marathon_eink::Waveform;

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, CONSTANT)]
        #[qproperty(bool, light_available, cxx_name = "lightAvailable", READ, CONSTANT)]
        #[qproperty(
            bool,
            proximity_available,
            cxx_name = "proximityAvailable",
            READ,
            CONSTANT
        )]
        #[qproperty(f64, brightness, READ, NOTIFY)]
        /// How much of the frame's light to keep, under 1 at the bottom of
        /// the slider on a panel whose dimmest level is still too bright.
        #[qproperty(f64, dim, READ, NOTIFY)]
        #[qproperty(bool, auto_brightness, cxx_name = "autoBrightness", READ, WRITE = set_auto_brightness, NOTIFY)]
        /// The level the user last chose, kept in settings and applied at
        /// start (a driver's boot default would win otherwise); -1 for none.
        #[qproperty(f64, user_brightness, cxx_name = "userBrightness", READ, WRITE = set_user_brightness, NOTIFY)]
        #[qproperty(bool, rotation_locked, cxx_name = "rotationLocked", READ, WRITE = set_rotation_locked, NOTIFY)]
        #[qproperty(bool, rotation_available, cxx_name = "rotationAvailable", READ, NOTIFY)]
        /// portrait, landscape, portrait-inverted or landscape-inverted.
        #[qproperty(QString, orientation, READ, NOTIFY)]
        #[qproperty(
            bool,
            night_light_enabled,
            cxx_name = "nightLightEnabled",
            READ,
            WRITE,
            NOTIFY
        )]
        #[qproperty(
            i32,
            night_light_temperature,
            cxx_name = "nightLightTemperature",
            READ,
            WRITE,
            NOTIFY
        )]
        /// nightLightTemperature as the 0 to 100 warmth the sliders show.
        #[qproperty(
            i32,
            night_light_temperature,
            cxx_name = "nightLightWarmth",
            READ = night_light_warmth,
            WRITE = set_night_light_warmth,
            NOTIFY = night_light_temperature_changed
        )]
        /// off, sunset (to sunrise) or custom (nightLightFrom to nightLightTo).
        #[qproperty(
            QString,
            night_light_schedule,
            cxx_name = "nightLightSchedule",
            READ,
            WRITE = set_night_light_schedule,
            NOTIFY
        )]
        /// Minutes after midnight.
        #[qproperty(i32, night_light_from, cxx_name = "nightLightFrom", READ, WRITE = set_night_light_from, NOTIFY)]
        #[qproperty(i32, night_light_to, cxx_name = "nightLightTo", READ, WRITE = set_night_light_to, NOTIFY)]
        /// What the user taught the brightness curve, as the settings keep it.
        #[qproperty(QString, learned_curve, cxx_name = "learnedCurve", READ, WRITE = set_learned_curve, NOTIFY)]
        /// The one record of whether the screen is on.
        #[qproperty(bool, screen_on, cxx_name = "screenOn", READ, NOTIFY)]
        #[qproperty(bool, proximity_near, cxx_name = "proximityNear", READ, NOTIFY)]
        /// Blanked at the ear in a call: touches are dropped as with the screen off.
        #[qproperty(bool, proximity_blanked, cxx_name = "proximityBlanked", READ, NOTIFY)]
        #[qproperty(i32, ambient_light, cxx_name = "ambientLight", READ, NOTIFY)]
        /// The screen is on as Nightshade's bedside clock: the backlight held
        /// at its lowest level, auto-brightness paused.
        #[qproperty(bool, nightshade, READ, WRITE = set_nightshade, NOTIFY)]
        /// An e-paper panel whose waveform the shell picks (eink.rs).
        #[qproperty(bool, refresh_controls, cxx_name = "refreshControls", READ, CONSTANT)]
        /// The waveform the panel is in: quality, text or fast.
        #[qproperty(QString, refresh_mode, cxx_name = "refreshMode", READ, NOTIFY)]
        /// Where it rests once still: quality or text.
        #[qproperty(QString, resting_refresh_mode, cxx_name = "restingRefreshMode", READ, WRITE = set_resting_refresh_mode, NOTIFY)]
        /// Clears the still screen's ghosts after enough fast drawing.
        #[qproperty(bool, auto_clear, cxx_name = "autoClear", READ, WRITE = set_auto_clear, NOTIFY)]
        /// A front light with warm LEDs (the profile's FRONTLIGHT_WARM): the
        /// night light warms it instead of tinting the frame.
        #[qproperty(
            bool,
            warm_light_available,
            cxx_name = "warmLightAvailable",
            READ,
            CONSTANT
        )]
        type Display = super::DisplayRust;

        /// Every turn on or off, so the compositor re-asserts the panel's
        /// power even when the state is unchanged.
        #[qsignal]
        #[cxx_name = "screenStateChanged"]
        fn screen_state_changed(self: Pin<&mut Self>, on: bool);

        #[cxx_name = "setAutoBrightness"]
        fn set_auto_brightness(self: Pin<&mut Display>, enabled: bool);
        #[cxx_name = "setRotationLocked"]
        fn set_rotation_locked(self: Pin<&mut Display>, locked: bool);
        #[cxx_name = "setLearnedCurve"]
        fn set_learned_curve(self: Pin<&mut Display>, curve: &QString);
        #[cxx_name = "nightLightWarmth"]
        fn night_light_warmth(self: &Display) -> i32;
        #[cxx_name = "setNightLightWarmth"]
        fn set_night_light_warmth(self: Pin<&mut Display>, warmth: i32);
        #[cxx_name = "setNightLightSchedule"]
        fn set_night_light_schedule(self: Pin<&mut Display>, schedule: &QString);
        #[cxx_name = "setNightLightFrom"]
        fn set_night_light_from(self: Pin<&mut Display>, minutes: i32);
        #[cxx_name = "setNightLightTo"]
        fn set_night_light_to(self: Pin<&mut Display>, minutes: i32);
        #[cxx_name = "setNightshade"]
        fn set_nightshade(self: Pin<&mut Display>, on: bool);
        #[cxx_name = "setRestingRefreshMode"]
        fn set_resting_refresh_mode(self: Pin<&mut Display>, mode: &QString);
        #[cxx_name = "setAutoClear"]
        fn set_auto_clear(self: Pin<&mut Display>, on: bool);

        /// The backlight under `backlight_dir`, the iio sensors under
        /// `iio_dir`, the lowest duty the panel is visible at, and the light
        /// the frame keeps at the bottom of the slider (1 for all of it).
        #[qinvokable]
        fn start(
            self: Pin<&mut Display>,
            backlight_dir: &QString,
            iio_dir: &QString,
            floor: f64,
            dim: f64,
        );
        /// The saved settings are applied: light the panel as they say.
        #[qinvokable]
        #[cxx_name = "applyRestored"]
        fn apply_restored(self: Pin<&mut Display>);
        #[qinvokable]
        #[cxx_name = "setBrightness"]
        fn set_brightness(self: Pin<&mut Display>, brightness: f64);
        /// A brightness the user chose, which the curve learns.
        #[qinvokable]
        #[cxx_name = "setBrightnessFromUser"]
        fn set_brightness_from_user(self: Pin<&mut Display>, brightness: f64);
        /// `reason` goes to the log when the screen was off.
        #[qinvokable]
        #[cxx_name = "turnScreenOn"]
        fn turn_screen_on(self: Pin<&mut Display>, reason: &QString);
        #[qinvokable]
        #[cxx_name = "turnScreenOff"]
        fn turn_screen_off(self: Pin<&mut Display>, reason: &QString);
        /// Turns the screen on and reports a wake even if it was on: after a
        /// suspend the shell can't know it went off.
        #[qinvokable]
        #[cxx_name = "forceScreenOn"]
        fn force_screen_on(self: Pin<&mut Display>);
        /// Powers the backlight down while a call holds the phone to an ear.
        #[qinvokable]
        #[cxx_name = "setProximityBlank"]
        fn set_proximity_blank(self: Pin<&mut Display>, blank: bool);
        #[qinvokable]
        #[cxx_name = "setProximityWanted"]
        fn set_proximity_wanted(self: Pin<&mut Display>, wanted: bool);
        /// An app is in the foreground: the only thing that turns.
        #[qinvokable]
        #[cxx_name = "setRotationWanted"]
        fn set_rotation_wanted(self: Pin<&mut Display>, wanted: bool);
        /// A key was pressed: the keyboard lights while the screen is on.
        #[qinvokable]
        #[cxx_name = "keyboardUsed"]
        fn keyboard_used(self: Pin<&mut Display>);
        /// The e-paper panel's flashing clear, once the screen is at rest.
        #[qinvokable]
        #[cxx_name = "fullRefresh"]
        fn full_refresh(self: &Display);
        /// Most of the screen changed at once (an app switch, unlock, Home):
        /// it counts toward the next automatic clear.
        #[qinvokable]
        #[cxx_name = "contentReplaced"]
        fn content_replaced(self: &Display);
        #[cxx_name = "setUserBrightness"]
        fn set_user_brightness(self: Pin<&mut Display>, value: f64);
    }

    impl cxx_qt::Threading for Display {}
}

use qobject::Display;

/// The display, for the I/O thread's services.
pub(crate) static DISPLAY: OnceLock<cxx_qt::CxxQtThread<Display>> = OnceLock::new();
static SCREEN_ON: AtomicBool = AtomicBool::new(true);

/// How long the keyboard stays lit after the last key or screen wake.
const KEYBOARD_LIGHT_TIMEOUT: Duration = Duration::from_secs(10);

/// Whether the screen is on, from any thread.
pub(crate) fn screen_on() -> bool {
    SCREEN_ON.load(Ordering::Relaxed)
}

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct DisplayRust {
    available: bool,
    light_available: bool,
    proximity_available: bool,
    brightness: f64,
    dim: f64,
    auto_brightness: bool,
    user_brightness: f64,
    rotation_locked: bool,
    rotation_available: bool,
    orientation: QString,
    night_light_enabled: bool,
    night_light_temperature: i32,
    night_light_schedule: QString,
    night_light_from: i32,
    night_light_to: i32,
    night_plans: Option<Sender<Plan>>,
    learned_curve: QString,
    screen_on: bool,
    proximity_near: bool,
    ambient_light: i32,
    panel: Option<Panel>,
    leds_dir: PathBuf,
    keyboards_lit: bool,
    keyboard_presses: u64,
    sensors: Option<Sender<(bool, bool)>>,
    accelerometer: Option<Sender<bool>>,
    rotation_wanted: bool,
    proximity_wanted: bool,
    proximity_blanked: bool,
    curve: Curve,
    smoothed_lux: Option<f64>,
    /// Since when the target has stayed brighter (true) or dimmer.
    dwell: Option<(bool, Instant)>,
    manual_at: Option<Instant>,
    lessons: u64,
    nightshade: bool,
    /// The brightness to come back to after Nightshade.
    day_brightness: f64,
    refresh_controls: bool,
    refresh_mode: QString,
    resting_refresh_mode: QString,
    auto_clear: bool,
    warm_light_available: bool,
    /// The white string's duty and the warm LEDs' when the shell started.
    boot_light: Option<(f64, f64)>,
}

impl Default for DisplayRust {
    fn default() -> Self {
        Self {
            available: false,
            light_available: false,
            proximity_available: false,
            brightness: 0.5,
            dim: 1.0,
            auto_brightness: false,
            user_brightness: -1.0,
            rotation_locked: false,
            rotation_available: false,
            orientation: QString::from("portrait"),
            night_light_enabled: false,
            night_light_temperature: 3400,
            night_light_schedule: QString::from("off"),
            night_light_from: 22 * 60,
            night_light_to: 7 * 60,
            night_plans: None,
            learned_curve: QString::default(),
            screen_on: true,
            proximity_near: false,
            ambient_light: 500,
            panel: None,
            leds_dir: PathBuf::from("/sys/class/leds"),
            keyboards_lit: false,
            keyboard_presses: 0,
            sensors: None,
            accelerometer: None,
            rotation_wanted: false,
            proximity_wanted: false,
            proximity_blanked: false,
            curve: Curve::default(),
            smoothed_lux: None,
            dwell: None,
            manual_at: None,
            lessons: 0,
            nightshade: false,
            day_brightness: 0.5,
            refresh_controls: false,
            refresh_mode: QString::from("quality"),
            resting_refresh_mode: QString::from("quality"),
            auto_clear: true,
            warm_light_available: false,
            boot_light: None,
        }
    }
}

/// Where the slider leaves the panel's lowest level and dims the frame instead.
const DIM_KNEE: f64 = 0.2;

/// The backlight as the user sees it: their 0..1 runs from the panel's
/// visible floor to full duty, on the nearest of its levels. With `dim`
/// under 1, the bottom of the slider holds the lowest level and darkens
/// the frame down to `dim` of its light.
struct Panel {
    dir: PathBuf,
    max: i32,
    floor: f64,
    dim: f64,
    actor: Sender<Command>,
    /// The share of its light the white string keeps; the warm LEDs have
    /// the rest.
    white: f64,
    warm: Option<WarmLight>,
}

/// A front light's warm LEDs: their `max_brightness` and their writer.
struct WarmLight {
    max: i32,
    actor: Sender<i32>,
}

impl Panel {
    fn knee(&self) -> f64 {
        if self.dim < 1.0 {
            DIM_KNEE
        } else {
            0.0
        }
    }

    fn duty(&self, user: f64) -> f64 {
        let knee = self.knee();
        let user = ((user - knee) / (1.0 - knee)).clamp(0.0, 1.0);
        self.floor + (1.0 - self.floor) * user
    }

    #[allow(clippy::cast_possible_truncation, reason = "at most max_brightness")]
    fn step(&self, duty: f64) -> i32 {
        ((duty * f64::from(self.max)).round() as i32).clamp(1, self.max)
    }

    /// The white string's level for `user`.
    fn level(&self, user: f64) -> i32 {
        self.step(self.duty(user) * self.white)
    }

    fn user(&self, level: i32) -> f64 {
        let knee = self.knee();
        let user = ((f64::from(level) / f64::from(self.max) - self.floor) / (1.0 - self.floor))
            .clamp(0.0, 1.0);
        knee + (1.0 - knee) * user
    }

    /// The share of the frame's light kept at `user`.
    fn dim(&self, user: f64) -> f64 {
        let knee = self.knee();
        if user >= knee {
            1.0
        } else {
            self.dim + (1.0 - self.dim) * user.max(0.0) / knee
        }
    }

    /// What the slider shows for `user` once it is on a level.
    fn shown(&self, user: f64) -> f64 {
        if user < self.knee() {
            user.max(0.0)
        } else {
            self.user(self.step(self.duty(user)))
        }
    }

    fn send(&self, command: Command) {
        if self.actor.try_send(command).is_err() {
            log::warn("display", "backlight busy; dropped a write");
        }
    }
}

impl Display {
    fn set_dim(mut self: Pin<&mut Self>, dim: f64) {
        if (self.dim - dim).abs() > f64::EPSILON {
            self.as_mut().rust_mut().dim = dim;
            self.dim_changed();
        }
    }

    fn start(
        mut self: Pin<&mut Self>,
        backlight_dir: &QString,
        iio_dir: &QString,
        floor: f64,
        dim: f64,
    ) {
        DISPLAY.set(self.qt_thread()).ok();
        if crate::device::VALUES.display_technology() == "epaper" {
            self.as_mut().rust_mut().refresh_controls =
                eink::start(Path::new("/sys/bus/i2c/devices"));
        }
        if let Some(class) = Path::new(&backlight_dir.to_string()).parent() {
            self.as_mut().rust_mut().leds_dir = class.join("leds");
        }
        // A shell that went away while the screen was off left them out.
        self.as_mut().keyboard_used();
        if let Some((dir, max, level)) = find_backlight(Path::new(&backlight_dir.to_string())) {
            let (tx, rx) = async_channel::bounded(64);
            io::spawn(backlight(dir.clone(), rx));
            let warm = crate::device::VALUES.frontlight_warm().and_then(|dir| {
                let warm_max = read(dir.join("max_brightness")).filter(|m: &i32| *m > 0)?;
                let lit = read(dir.join("brightness")).unwrap_or(0);
                let (tx, rx) = async_channel::bounded(16);
                io::spawn(warm_light(dir, rx));
                Some((
                    WarmLight {
                        max: warm_max,
                        actor: tx,
                    },
                    lit,
                ))
            });
            let warm_lit = warm
                .as_ref()
                .map_or(0.0, |(w, lit)| f64::from(*lit) / f64::from(w.max));
            let panel = Panel {
                dir,
                max,
                floor,
                dim: dim.clamp(0.05, 1.0),
                actor: tx,
                white: 1.0,
                warm: warm.map(|(w, _)| w),
            };
            let mut rust = self.as_mut().rust_mut();
            rust.brightness = level.map_or(0.5, |l| panel.user(l));
            rust.boot_light = level.map(|l| (f64::from(l) / f64::from(max), warm_lit));
            rust.available = true;
            rust.warm_light_available = panel.warm.is_some();
            rust.panel = Some(panel);
        }
        if let Some(channels) = find_sensors(Path::new(&iio_dir.to_string())) {
            let (tx, rx) = async_channel::bounded(8);
            io::spawn(sensors(self.qt_thread(), channels.clone(), rx));
            let mut rust = self.as_mut().rust_mut();
            rust.light_available = true;
            rust.proximity_available = channels.proximity.is_some();
            rust.sensors = Some(tx);
        }
        let (tx, rx) = async_channel::bounded(8);
        let qt = self.qt_thread();
        io::each_system_bus(move |bus| rotation(qt.clone(), bus, rx.clone()));
        self.as_mut().rust_mut().accelerometer = Some(tx);
        self.want_sensors();
        let (tx, rx) = async_channel::bounded(8);
        io::spawn(night_light::run(self.qt_thread(), rx));
        self.as_mut().rust_mut().night_plans = Some(tx);
        self.plan_night_light();
        let push = |obj: Pin<&mut Self>| ipc::signal("Display", "StateChanged", (state(&obj),));
        self.as_mut().on_auto_brightness_changed(push).release();
        self.as_mut().on_rotation_locked_changed(push).release();
        self.as_mut().on_rotation_available_changed(push).release();
        self.as_mut().on_brightness_changed(push).release();
        self.as_mut().on_night_light_enabled_changed(push).release();
        self.as_mut()
            .on_night_light_temperature_changed(push)
            .release();
        self.as_mut()
            .on_night_light_schedule_changed(push)
            .release();
        self.as_mut().on_night_light_from_changed(push).release();
        self.as_mut().on_night_light_to_changed(push).release();
        self.as_mut().on_screen_on_changed(push).release();
        self.as_mut()
            .on_resting_refresh_mode_changed(push)
            .release();
        self.as_mut().on_auto_clear_changed(push).release();
        self.as_mut()
            .on_proximity_near_changed(|obj| {
                ipc::signal("Sensor", "ProximityChanged", (obj.proximity_near,));
            })
            .release();
        self.as_mut()
            .on_ambient_light_changed(|obj| {
                ipc::signal("Sensor", "AmbientLightChanged", (obj.ambient_light,));
            })
            .release();
        let qt = self.qt_thread();
        ipc::export("Display", Display1 { qt: qt.clone() });
        ipc::export("Sensor", Sensor1 { qt });
    }

    /// Once the saved settings are on: the panel lit at the user's last
    /// level (else the light it had), with the night light's warm share,
    /// and the warm light following it.
    fn apply_restored(mut self: Pin<&mut Self>) {
        let Some(panel) = &self.panel else { return };
        let start = start_brightness(
            panel,
            self.user_brightness,
            self.boot_light,
            self.night_light_enabled,
        );
        if let Some(brightness) = start {
            let dim = panel.dim(brightness);
            self.as_mut().rust_mut().brightness = brightness;
            self.as_mut().brightness_changed();
            self.as_mut().set_dim(dim);
        }
        if self.warm_light_available {
            let mix = |obj: Pin<&mut Self>| obj.mix_front_light();
            self.as_mut().on_brightness_changed(mix).release();
            self.as_mut().on_night_light_enabled_changed(mix).release();
            self.as_mut()
                .on_night_light_temperature_changed(mix)
                .release();
            self.as_mut().on_screen_on_changed(mix).release();
            self.as_mut().on_proximity_blanked_changed(mix).release();
            self.as_mut().mix_front_light();
        }
        if let Some(panel) = &self.panel {
            panel.send(Command::Level(panel.level(self.brightness)));
        }
    }

    fn set_brightness(mut self: Pin<&mut Self>, brightness: f64) {
        if self.nightshade {
            self.as_mut().rust_mut().day_brightness = brightness;
            return;
        }
        let Some(panel) = &self.panel else { return };
        let shown = panel.shown(brightness);
        let dim = panel.dim(shown);
        panel.send(Command::Level(panel.level(brightness)));
        let mut rust = self.as_mut().rust_mut();
        // The user's level wins over auto-brightness for a while.
        rust.manual_at = Some(Instant::now());
        rust.brightness = shown;
        self.as_mut().brightness_changed();
        self.as_mut().set_dim(dim);
    }

    fn set_brightness_from_user(mut self: Pin<&mut Self>, brightness: f64) {
        self.as_mut().set_brightness(brightness);
        let chosen = self.brightness;
        self.as_mut().set_user_brightness(chosen);
        if !self.auto_brightness {
            return;
        }
        let lux = self
            .smoothed_lux
            .unwrap_or_else(|| f64::from(self.ambient_light));
        let lesson = {
            let mut rust = self.as_mut().rust_mut();
            rust.curve.teach(brightness, lux);
            rust.lessons += 1;
            rust.lessons
        };
        // A slider drag teaches once, where the finger settles.
        let qt = self.qt_thread();
        io::spawn(async move {
            Timer::after(Duration::from_millis(600)).await;
            qt.queue(move |mut obj| {
                if obj.lessons == lesson {
                    let mut rust = obj.as_mut().rust_mut();
                    rust.curve.learn();
                    rust.learned_curve = QString::from(&rust.curve.to_string());
                    obj.learned_curve_changed();
                }
            })
            .ok();
        });
    }

    fn set_learned_curve(mut self: Pin<&mut Self>, curve: &QString) {
        let mut rust = self.as_mut().rust_mut();
        rust.curve = curve.to_string().parse().unwrap_or_default();
        rust.learned_curve = curve.clone();
        self.learned_curve_changed();
    }

    fn set_night_light_schedule(mut self: Pin<&mut Self>, schedule: &QString) {
        set!(
            self,
            night_light_schedule,
            night_light_schedule_changed,
            schedule.clone()
        );
        self.plan_night_light();
    }

    fn set_night_light_from(mut self: Pin<&mut Self>, minutes: i32) {
        set!(
            self,
            night_light_from,
            night_light_from_changed,
            minutes.rem_euclid(1440)
        );
        self.plan_night_light();
    }

    fn set_night_light_to(mut self: Pin<&mut Self>, minutes: i32) {
        set!(
            self,
            night_light_to,
            night_light_to_changed,
            minutes.rem_euclid(1440)
        );
        self.plan_night_light();
    }

    fn night_light_warmth(&self) -> i32 {
        warmth(self.night_light_temperature)
    }

    fn set_night_light_warmth(mut self: Pin<&mut Self>, warmth: i32) {
        self.as_mut().set_night_light_temperature(kelvin(warmth));
    }

    /// The night light's part of the front light, lit with the screen.
    fn mix_front_light(mut self: Pin<&mut Self>) {
        let Some(panel) = &self.panel else { return };
        let Some(warm) = &panel.warm else { return };
        let night = self
            .night_light_enabled
            .then(|| warmth(self.night_light_temperature));
        let (white, level) = front_light(panel.duty(self.brightness), night, warm.max);
        let lit = self.screen_on && !self.proximity_blanked;
        warm.actor.try_send(if lit { level } else { 0 }).ok();
        if (panel.white - white).abs() > f64::EPSILON {
            let brightness = self.brightness;
            let mut rust = self.as_mut().rust_mut();
            let Some(panel) = rust.panel.as_mut() else {
                return;
            };
            panel.white = white;
            panel.send(Command::Level(panel.level(brightness)));
        }
    }

    /// Hands the schedule to its timer, which applies it now.
    fn plan_night_light(&self) {
        let schedule = match self.night_light_schedule.to_string().as_str() {
            "sunset" => Schedule::Sunset,
            "custom" => Schedule::Times(self.night_light_from, self.night_light_to),
            _ => Schedule::Manual,
        };
        if let Some(plans) = &self.night_plans {
            plans.try_send(Plan::Set(schedule)).ok();
        }
    }

    fn set_rotation_locked(mut self: Pin<&mut Self>, locked: bool) {
        set!(self, rotation_locked, rotation_locked_changed, locked);
        self.want_sensors();
    }

    fn set_resting_refresh_mode(mut self: Pin<&mut Self>, mode: &QString) {
        // Only quality and text can rest: clean flashes on every return.
        let Some(w) = Waveform::parse(&mode.to_string())
            .filter(|w| matches!(w, Waveform::Quality | Waveform::Text))
        else {
            return;
        };
        eink::set_resting(w);
        set!(
            self,
            resting_refresh_mode,
            resting_refresh_mode_changed,
            QString::from(w.name())
        );
    }

    fn set_auto_clear(mut self: Pin<&mut Self>, on: bool) {
        eink::set_auto_clear(on);
        set!(self, auto_clear, auto_clear_changed, on);
    }

    #[allow(clippy::float_cmp, reason = "a change is any new value")]
    fn set_user_brightness(mut self: Pin<&mut Self>, value: f64) {
        set!(self, user_brightness, user_brightness_changed, value);
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn full_refresh(&self) {
        eink::refresh();
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn content_replaced(&self) {
        eink::replaced();
    }

    fn set_auto_brightness(mut self: Pin<&mut Self>, enabled: bool) {
        // Off, and not settable, without a light sensor.
        set!(
            self,
            auto_brightness,
            auto_brightness_changed,
            enabled && self.light_available
        );
        self.want_sensors();
    }

    fn lux(mut self: Pin<&mut Self>, lux: i32) {
        set!(self, ambient_light, ambient_light_changed, lux);
        if !self.auto_brightness
            || self.nightshade
            || self
                .manual_at
                .is_some_and(|t| t.elapsed() < Duration::from_secs(5))
        {
            return;
        }
        let raw = f64::from(lux);
        let smoothed = self.smoothed_lux.map_or(raw, |l| 0.25 * raw + 0.75 * l);
        let target = self.curve.target(smoothed);
        let delta = target - self.brightness;
        let mut rust = self.as_mut().rust_mut();
        rust.smoothed_lux = Some(smoothed);
        // A deadband, so the panel never hunts; then brighten fast, dim slowly.
        if delta.abs() < 0.06 {
            rust.dwell = None;
            return;
        }
        let brighter = delta > 0.0;
        let since = match rust.dwell {
            Some((b, since)) if b == brighter => since,
            _ => Instant::now(),
        };
        if since.elapsed() < Duration::from_millis(if brighter { 300 } else { 1500 }) {
            rust.dwell = Some((brighter, since));
            return;
        }
        rust.dwell = None;
        self.ramp_to(target);
    }

    /// Down to the panel's lowest level without dimming the frame (or stays
    /// dimmer), and back. A level set meanwhile is kept for the way back.
    fn set_nightshade(mut self: Pin<&mut Self>, on: bool) {
        if self.nightshade == on {
            return;
        }
        let target = if on {
            let day = self.brightness;
            self.as_mut().rust_mut().day_brightness = day;
            self.as_mut().set_keyboards_lit(false);
            self.panel.as_ref().map_or(0.0, Panel::knee).min(day)
        } else {
            self.day_brightness
        };
        if self.screen_on {
            self.as_mut().ramp_to(target);
        } else if let Some(panel) = &self.panel {
            let dim = panel.dim(target);
            self.as_mut().rust_mut().brightness = target;
            self.as_mut().brightness_changed();
            self.as_mut().set_dim(dim);
        }
        set!(self, nightshade, nightshade_changed, on);
        self.want_sensors();
    }

    /// A smoothstep over 600 ms, as the hardware levels it passes.
    fn ramp_to(mut self: Pin<&mut Self>, target: f64) {
        let Some(panel) = &self.panel else { return };
        let from = self.brightness;
        let levels = (1..=30)
            .map(|i| {
                let t = f64::from(i) / 30.0;
                panel.level(from + (target - from) * t * t * (3.0 - 2.0 * t))
            })
            .collect();
        panel.send(Command::Ramp(levels));
        let dim = panel.dim(target);
        self.as_mut().rust_mut().brightness = target;
        self.as_mut().brightness_changed();
        self.as_mut().set_dim(dim);
    }

    pub(crate) fn turn_screen_on(self: Pin<&mut Self>, reason: &QString) {
        if !self.screen_on {
            log::warn("display", format_args!("screen on by {reason}"));
        }
        self.set_screen(true);
    }

    fn turn_screen_off(self: Pin<&mut Self>, reason: &QString) {
        log::warn("display", format_args!("screen off by {reason}"));
        self.set_screen(false);
    }

    fn force_screen_on(mut self: Pin<&mut Self>) {
        log::warn("display", "screen on by resume from suspend");
        let was_on = self.screen_on;
        self.as_mut().set_screen(true);
        if was_on {
            self.screen_on_changed();
        }
    }

    // screenStateChanged powers the CRTC on or off before it returns, and a
    // backlight write while the display's power domain is gated is dropped:
    // so the LED goes down before the CRTC, and comes up after it.
    fn set_screen(mut self: Pin<&mut Self>, on: bool) {
        if !on {
            self.as_mut().set_keyboards_lit(false);
        }
        if let (false, Some(panel)) = (on, &self.panel) {
            if let Err(e) = fs::write(panel.dir.join("bl_power"), "4\n") {
                log::warn("display", format_args!("bl_power: {e}"));
            }
            panel.send(Command::Sleep);
        }
        set!(self, screen_on, screen_on_changed, on);
        SCREEN_ON.store(on, Ordering::Relaxed);
        eink::screen(on);
        crate::status_led::screen(on);
        if on {
            self.as_mut().keyboard_used();
        }
        crate::power::state_changed();
        self.as_mut().screen_state_changed(on);
        if let (true, Some(panel)) = (on, &self.panel) {
            panel.send(Command::Wake(panel.level(self.brightness)));
        }
        if let (true, Some(plans)) = (on, &self.night_plans) {
            plans.try_send(Plan::Check).ok();
        }
        self.want_sensors();
    }

    fn set_proximity_blank(mut self: Pin<&mut Self>, blank: bool) {
        if self.proximity_blanked == blank {
            return;
        }
        let Some(panel) = &self.panel else { return };
        if blank {
            log::warn("display", "screen off by proximity during a call");
        }
        panel.send(Command::Blank(blank, panel.level(self.brightness)));
        self.as_mut().rust_mut().proximity_blanked = blank;
        self.proximity_blanked_changed();
    }

    fn set_rotation_wanted(mut self: Pin<&mut Self>, wanted: bool) {
        self.as_mut().rust_mut().rotation_wanted = wanted;
        self.want_sensors();
    }

    fn set_proximity_wanted(mut self: Pin<&mut Self>, wanted: bool) {
        self.as_mut().rust_mut().proximity_wanted = wanted;
        // A stale "near" must not outlive the call.
        if !wanted {
            set!(self, proximity_near, proximity_near_changed, false);
        }
        self.want_sensors();
    }

    fn keyboard_used(mut self: Pin<&mut Self>) {
        if !self.screen_on {
            return;
        }
        self.as_mut().set_keyboards_lit(true);
        let press = {
            let mut rust = self.as_mut().rust_mut();
            rust.keyboard_presses += 1;
            rust.keyboard_presses
        };
        let qt = self.qt_thread();
        io::spawn(async move {
            Timer::after(KEYBOARD_LIGHT_TIMEOUT).await;
            qt.queue(move |mut obj| {
                if obj.keyboard_presses == press {
                    obj.as_mut().set_keyboards_lit(false);
                }
            })
            .ok();
        });
    }

    fn set_keyboards_lit(mut self: Pin<&mut Self>, on: bool) {
        if self.keyboards_lit != on {
            self.as_mut().rust_mut().keyboards_lit = on;
            light_keyboards(&self.leds_dir, on);
        }
    }

    /// Light while auto-brightness has a lit screen to set; proximity while
    /// a call wants it; the accelerometer while a lit screen shows an app
    /// that may rotate.
    fn want_sensors(&self) {
        if let Some(sensors) = &self.sensors {
            sensors
                .try_send((
                    self.auto_brightness && self.screen_on && !self.nightshade,
                    self.proximity_wanted,
                ))
                .ok();
        }
        if let Some(accelerometer) = &self.accelerometer {
            accelerometer
                .try_send(self.screen_on && self.rotation_wanted && !self.rotation_locked)
                .ok();
        }
    }
}

/// Every keyboard light full on, or out. Nothing sets their level, so on is
/// the keyboard's own: its `max_brightness`.
fn light_keyboards(leds: &Path, on: bool) {
    let Ok(entries) = fs::read_dir(leds) else {
        return;
    };
    for entry in entries.flatten() {
        if !entry
            .file_name()
            .to_string_lossy()
            .ends_with("::kbd_backlight")
        {
            continue;
        }
        let dir = entry.path();
        let level = if on {
            fs::read_to_string(dir.join("max_brightness")).unwrap_or_default()
        } else {
            "0".to_owned()
        };
        if let Err(e) = fs::write(dir.join("brightness"), level.trim()) {
            log::warn("display", format_args!("{}: {e}", dir.display()));
        }
    }
}

/// The panel's backlight, its `max_brightness` and its level now.
fn find_backlight(root: &Path) -> Option<(PathBuf, i32, Option<i32>)> {
    let mut names: Vec<_> = fs::read_dir(root)
        .ok()?
        .flatten()
        .map(|e| e.file_name())
        .collect();
    names.sort();
    let name = ["apple-panel-bl", "intel_backlight"]
        .iter()
        .find_map(|p| names.iter().find(|n| *n == *p))
        .or_else(|| names.first())?;
    let dir = root.join(name);
    let max = read(dir.join("max_brightness")).filter(|m| *m > 0)?;
    let level = read(dir.join("brightness"));
    Some((dir, max, level))
}

#[derive(Clone)]
struct Channels {
    light: PathBuf,
    lux_scale: f64,
    proximity: Option<PathBuf>,
    near_level: i32,
}

fn find_sensors(root: &Path) -> Option<Channels> {
    let mut dirs: Vec<_> = fs::read_dir(root)
        .ok()?
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .is_some_and(|n| n.to_string_lossy().starts_with("iio:device"))
        })
        .collect();
    dirs.sort();
    let dir = dirs
        .into_iter()
        .find(|d| d.join("in_illuminance_raw").exists())?;
    Some(Channels {
        light: dir.join("in_illuminance_raw"),
        lux_scale: read(dir.join("in_illuminance_scale"))
            .filter(|s| *s > 0.0)
            .unwrap_or(1.0),
        proximity: Some(dir.join("in_proximity_raw")).filter(|p| p.exists()),
        near_level: read(dir.join("in_proximity_nearlevel"))
            .filter(|l| *l > 0)
            .unwrap_or(16),
    })
}

const ANCHORS: usize = 9;

/// Lux to brightness: a perceptual log curve plus what the user taught it.
/// A long-term offset per half decade of lux drifts toward their corrections
/// across sessions; the last correction applies exactly in the light it was
/// made in, relaxing to the long term as the light moves away.
#[derive(Default)]
struct Curve {
    long_term: [f64; ANCHORS],
    /// The last correction: its log lux and offset.
    short_term: Option<(f64, f64)>,
}

fn log_lux(lux: f64) -> f64 {
    (lux.max(0.0) + 1.0).log10()
}

/// 0 lux is just above the floor, 10000 (direct sun) is full.
fn base(lux: f64) -> f64 {
    (0.05 + 0.24 * log_lux(lux)).clamp(0.0, 1.0)
}

/// The anchor below `log_lux` and how far it is toward the next.
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_precision_loss,
    reason = "0 to 8"
)]
fn anchor(log_lux: f64) -> (usize, f64) {
    let f = log_lux.clamp(0.0, 4.0) / 0.5;
    let i = (f.floor() as usize).min(ANCHORS - 2);
    (i, f - i as f64)
}

impl Curve {
    fn target(&self, lux: f64) -> f64 {
        let ll = log_lux(lux);
        let (i, t) = anchor(ll);
        let long = self.long_term[i] * (1.0 - t) + self.long_term[i + 1] * t;
        let offset = self.short_term.map_or(long, |(at, short)| {
            let d = (ll - at) / 0.6;
            long + (-d * d).exp() * (short - long)
        });
        (base(lux) + offset).clamp(0.05, 1.0)
    }

    fn teach(&mut self, user: f64, lux: f64) {
        self.short_term = Some((log_lux(lux), (user - base(lux)).clamp(-0.5, 0.5)));
    }

    /// Blends the two anchors around the last correction halfway toward it.
    fn learn(&mut self) {
        let Some((ll, offset)) = self.short_term else {
            return;
        };
        let (i, _) = anchor(ll);
        for o in &mut self.long_term[i..=i + 1] {
            *o = (*o + 0.5 * (offset.clamp(-0.4, 0.4) - *o)).clamp(-0.4, 0.4);
        }
    }
}

impl std::fmt::Display for Curve {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let offsets: Vec<String> = self.long_term.iter().map(|o| format!("{o:.4}")).collect();
        f.write_str(&offsets.join(","))
    }
}

impl FromStr for Curve {
    type Err = std::num::ParseFloatError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let mut curve = Self::default();
        for (o, v) in curve
            .long_term
            .iter_mut()
            .zip(s.split(',').filter(|v| !v.is_empty()))
        {
            *o = v.trim().parse::<f64>()?.clamp(-0.4, 0.4);
        }
        Ok(curve)
    }
}

/// The night light's warmth, 0 to 100, over 4500 K (mild) to 2700 K
/// (candlelight), as the Settings app's slider (SettingsLogic.js).
#[allow(clippy::cast_possible_truncation, reason = "0 to 100")]
fn warmth(kelvin: i32) -> i32 {
    ((4500.0 - f64::from(kelvin)) / 18.0)
        .round()
        .clamp(0.0, 100.0) as i32
}

/// Unlike the Settings app's, not rounded to 100 K: each warmth its own.
fn kelvin(warmth: i32) -> i32 {
    4500 - warmth.clamp(0, 100) * 18
}

/// A front light at white `duty` (0 to 1) with the night light on at a
/// warmth (0 to 100), or off: the white string's share of its light, and
/// the warm LEDs' level out of `warm_max`. The warm LEDs take what the
/// white gives up, so the light warms without dimming.
#[allow(clippy::cast_possible_truncation, reason = "at most warm_max")]
fn front_light(duty: f64, night: Option<i32>, warm_max: i32) -> (f64, i32) {
    let warm = f64::from(night.unwrap_or(0).clamp(0, 100)) / 100.0;
    let level = (duty.clamp(0.0, 1.0) * warm * f64::from(warm_max)).round() as i32;
    (1.0 - warm, level)
}

/// The light a front light had, as a white duty, from the white string's
/// duty and the warm LEDs': the warm LEDs carry what the white gave up
/// while the night light is on. Lit with it off, they are the driver's
/// default, not part of the light.
fn boot_duty(white: f64, warm: f64, night: bool) -> f64 {
    (white + if night { warm } else { 0.0 }).min(1.0)
}

/// The brightness to start at: the user's last choice, else the light the
/// panel had (`boot_light`, white and warm duties), else none.
fn start_brightness(
    panel: &Panel,
    user: f64,
    boot_light: Option<(f64, f64)>,
    night: bool,
) -> Option<f64> {
    if user >= 0.0 {
        return Some(panel.shown(user.min(1.0)));
    }
    let (white, warm) = boot_light?;
    #[allow(clippy::cast_possible_truncation, reason = "at most max_brightness")]
    let level = (boot_duty(white, warm, night) * f64::from(panel.max)).round() as i32;
    Some(panel.user(level.max(1)))
}

/// Writes the warm LEDs' level, the last of those queued.
async fn warm_light(dir: PathBuf, levels: Receiver<i32>) {
    let path = dir.join("brightness");
    let mut written = None;
    while let Ok(first) = levels.recv().await {
        let level = std::iter::from_fn(|| levels.try_recv().ok())
            .last()
            .unwrap_or(first);
        if written == Some(level) {
            continue;
        }
        match fs::write(&path, format!("{level}\n")) {
            Ok(()) => written = Some(level),
            Err(e) => log::warn("display", format_args!("{}: {e}", path.display())),
        }
    }
}

enum Command {
    Level(i32),
    /// Levels 20 ms apart; a later level or ramp replaces it.
    Ramp(Vec<i32>),
    /// Power-cycles the LED and writes the level, checking it lit.
    Wake(i32),
    Sleep,
    Blank(bool, i32),
}

async fn backlight(dir: PathBuf, commands: Receiver<Command>) {
    let mut led = Led { dir, written: None };
    let mut ramp: VecDeque<i32> = VecDeque::new();
    // Checks left after a wake, and its level: a write racing the CRTC's
    // power-up is dropped, and the panel stays dark.
    let mut checks = (0u8, 0);
    loop {
        let tick = if !ramp.is_empty() {
            Some(Duration::from_millis(20))
        } else if checks.0 > 0 {
            Some(Duration::from_millis(120))
        } else {
            None
        };
        match io::recv_within(&commands, tick).await {
            Some(Err(_)) => return,
            Some(Ok(first)) => {
                for command in collapse(first, &commands) {
                    match command {
                        Command::Level(level) => {
                            ramp.clear();
                            led.level(level).await;
                        }
                        Command::Ramp(mut levels) => {
                            levels.dedup();
                            ramp = levels.into();
                        }
                        Command::Wake(level) => {
                            ramp.clear();
                            if !led.power_cycle(level, &commands).await {
                                return;
                            }
                            checks = (3, level);
                        }
                        Command::Sleep => {
                            ramp.clear();
                            checks.0 = 0;
                            led.write("bl_power", "4");
                        }
                        Command::Blank(blank, level) => {
                            led.write("bl_power", if blank { "4" } else { "0" });
                            if !blank {
                                led.written = None;
                                led.level(level).await;
                            }
                        }
                    }
                }
            }
            None => {
                if let Some(level) = ramp.pop_front() {
                    led.level(level).await;
                } else if read::<i32>(led.dir.join("bl_power")) == Some(0) {
                    checks.0 = 0;
                } else {
                    checks.0 -= 1;
                    log::warn(
                        "display",
                        "the panel is still dark after a wake; lighting it again",
                    );
                    if !led.power_cycle(checks.1, &commands).await {
                        return;
                    }
                }
            }
        }
    }
}

/// `first` and everything queued behind it, each run of levels collapsed
/// to its last: a slider drag writes where the finger is, not every step
/// it passed.
fn collapse(first: Command, commands: &Receiver<Command>) -> Vec<Command> {
    let mut batch: Vec<Command> = Vec::new();
    for command in std::iter::once(first).chain(std::iter::from_fn(|| commands.try_recv().ok())) {
        if let (Command::Level(_), Some(Command::Level(_))) = (&command, batch.last()) {
            batch.pop();
        }
        batch.push(command);
    }
    batch
}

struct Led {
    dir: PathBuf,
    written: Option<i32>,
}

#[zbus::proxy(
    interface = "org.freedesktop.login1.Session",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1/session/auto"
)]
trait Session {
    fn set_brightness(&self, subsystem: &str, name: &str, brightness: u32) -> zbus::Result<()>;
}

impl Led {
    fn write(&self, file: &str, value: &str) {
        if let Err(e) = fs::write(self.dir.join(file), format!("{value}\n")) {
            log::warn("display", format_args!("{file}: {e}"));
        }
    }

    async fn level(&mut self, level: i32) {
        if self.written == Some(level) {
            return;
        }
        let written = match fs::write(self.dir.join("brightness"), format!("{level}\n")) {
            // Without the device's udev rule, logind sets it for the session.
            Err(e) if e.kind() == ErrorKind::PermissionDenied => self.set_by_logind(level).await,
            other => other.map_err(zbus::Error::from),
        };
        match written {
            Ok(()) => self.written = Some(level),
            Err(e) => log::warn("display", format_args!("brightness: {e}")),
        }
    }

    async fn set_by_logind(&self, level: i32) -> zbus::Result<()> {
        let name = self
            .dir
            .file_name()
            .map_or_default(|n| n.to_string_lossy().into_owned());
        let session = SessionProxy::new(&io::system_bus().await?).await?;
        session
            .set_brightness("backlight", &name, u32::try_from(level).unwrap_or(0))
            .await
    }

    /// After deep-idle Doze a pwm-backlight duty can stay latched at 0, and
    /// a plain `bl_power` 0 leaves the panel dark. False if the display went
    /// while the LED was down.
    async fn power_cycle(&mut self, level: i32, commands: &Receiver<Command>) -> bool {
        self.write("bl_power", "4");
        Timer::after(Duration::from_millis(30)).await;
        if commands.is_closed() {
            return false;
        }
        self.write("bl_power", "0");
        // Two stores, so pwm_backlight_update_status re-applies the duty:
        // one idempotent write can be skipped.
        self.write("brightness", "1");
        self.written = None;
        self.level(level).await;
        true
    }
}

/// Polls only the channels wanted, reporting changes: every 200 ms while
/// proximity is wanted (calls), else every second.
async fn sensors(
    qt: cxx_qt::CxxQtThread<Display>,
    channels: Channels,
    wanted: Receiver<(bool, bool)>,
) {
    let (mut light, mut proximity) = (false, false);
    let (mut last_lux, mut last_near) = (None, None);
    loop {
        let every =
            (light || proximity).then(|| Duration::from_millis(if proximity { 200 } else { 1000 }));
        match io::recv_within(&wanted, every).await {
            Some(Err(_)) => return,
            // A channel just asked for is read, and reported, at once.
            Some(Ok((l, p))) => {
                if l && !light {
                    last_lux = None;
                }
                if p && !proximity {
                    last_near = None;
                }
                (light, proximity) = (l, p);
            }
            None => {}
        }
        if light {
            if let Some(raw) = measure(channels.light.clone()).await {
                #[allow(clippy::cast_possible_truncation, reason = "lux fits an i32")]
                let lux = (f64::from(raw) * channels.lux_scale).round() as i32;
                if last_lux != Some(lux) {
                    last_lux = Some(lux);
                    qt.queue(move |obj| obj.lux(lux)).ok();
                }
            }
        }
        if let (true, Some(path)) = (proximity, channels.proximity.clone()) {
            let near = measure(path).await.unwrap_or(0) >= channels.near_level;
            if last_near != Some(near) {
                last_near = Some(near);
                qt.queue(move |mut obj| set!(obj, proximity_near, proximity_near_changed, near))
                    .ok();
            }
        }
    }
}

#[zbus::proxy(
    interface = "net.hadess.SensorProxy",
    default_service = "net.hadess.SensorProxy",
    default_path = "/net/hadess/SensorProxy"
)]
trait SensorProxy {
    fn claim_accelerometer(&self) -> zbus::Result<()>;
    fn release_accelerometer(&self) -> zbus::Result<()>;
    #[zbus(property)]
    fn has_accelerometer(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn accelerometer_orientation(&self) -> zbus::Result<String>;
}

fn orientation(proxy: &str) -> Option<&'static str> {
    match proxy {
        "normal" => Some("portrait"),
        "right-up" => Some("landscape"),
        "bottom-up" => Some("portrait-inverted"),
        "left-up" => Some("landscape-inverted"),
        _ => None,
    }
}

/// What the accelerometer follower has for the Display.
#[derive(Debug, PartialEq)]
enum Turn {
    Available,
    Orientation(&'static str),
}

/// Why following the accelerometer stopped.
enum Followed {
    /// No accelerometer, or nobody left to want one: for good.
    Done,
    /// iio-sensor-proxy went away or was replaced: follow it again.
    Lost,
}

/// A follower that ends this soon after it started waits twice as long
/// before the next, so a proxy that keeps failing does not spin.
const FOLLOW_RETRY: Duration = Duration::from_millis(250);
const FOLLOW_RETRY_MAX: Duration = Duration::from_secs(32);
const FOLLOW_SHORT_LIVED: Duration = Duration::from_secs(10);

/// Follows the accelerometer while it is wanted, and iio-sensor-proxy
/// again each time it restarts: a new one has lost the claim, so it would
/// never report another turn.
async fn rotation(qt: cxx_qt::CxxQtThread<Display>, bus: zbus::Connection, wanted: Receiver<bool>) {
    let report = move |turn| {
        qt.queue(move |mut obj| match turn {
            Turn::Available => set!(obj, rotation_available, rotation_available_changed, true),
            Turn::Orientation(o) => {
                set!(obj, orientation, orientation_changed, QString::from(o))
            }
        })
        .ok();
    };
    follow_rotation(&bus, &wanted, &report).await;
}

async fn follow_rotation(bus: &zbus::Connection, wanted: &Receiver<bool>, report: &impl Fn(Turn)) {
    let mut want = false;
    let mut retry = FOLLOW_RETRY;
    loop {
        let started = Instant::now();
        match follow_accelerometer(bus, wanted, &mut want, report).await {
            Ok(Followed::Done) => return,
            Ok(Followed::Lost) => {}
            Err(e) => log::warn("display", format_args!("accelerometer: {e}")),
        }
        if started.elapsed() >= FOLLOW_SHORT_LIVED {
            retry = FOLLOW_RETRY;
        }
        Timer::after(retry).await;
        retry = (retry * 2).min(FOLLOW_RETRY_MAX);
    }
}

/// One iio-sensor-proxy's accelerometer, claimed while `want` is true.
async fn follow_accelerometer(
    bus: &zbus::Connection,
    wanted: &Receiver<bool>,
    want: &mut bool,
    report: &impl Fn(Turn),
) -> zbus::Result<Followed> {
    let proxy = SensorProxyProxy::new(bus).await?;
    let mut owners = proxy.inner().receive_owner_changed().await?;
    if !proxy.has_accelerometer().await? {
        return Ok(Followed::Done);
    }
    report(Turn::Available);
    let mut turns = proxy.receive_accelerometer_orientation_changed().await;
    let mut claimed = false;
    loop {
        if *want != claimed {
            if *want {
                proxy.claim_accelerometer().await?;
                claimed = true;
                if let Some(o) = orientation(&proxy.accelerometer_orientation().await?) {
                    report(Turn::Orientation(o));
                }
            } else {
                proxy.release_accelerometer().await?;
                claimed = false;
                // Stale once released: the next claim reads it afresh.
                report(Turn::Orientation("portrait"));
            }
        }
        let next = future::or(
            future::or(async { Event::Wanted(wanted.recv().await.ok()) }, async {
                Event::Turned(turns.next().await)
            }),
            async { Event::Owner(owners.next().await) },
        )
        .await;
        match next {
            Event::Wanted(None) => return Ok(Followed::Done),
            Event::Wanted(Some(w)) => *want = w,
            Event::Turned(None) | Event::Owner(_) => return Ok(Followed::Lost),
            Event::Turned(Some(turn)) if claimed => {
                if let Some(o) = turn.get().await.ok().as_deref().and_then(orientation) {
                    report(Turn::Orientation(o));
                }
            }
            Event::Turned(Some(_)) => {}
        }
    }
}

enum Event<T, O> {
    Wanted(Option<bool>),
    Turned(Option<T>),
    Owner(Option<O>),
}

/// The policy thread put the panel in `w`.
pub(crate) fn panel_waveform(w: Waveform) {
    if let Some(qt) = DISPLAY.get() {
        qt.queue(move |mut obj| {
            set!(
                obj,
                refresh_mode,
                refresh_mode_changed,
                QString::from(w.name())
            );
        })
        .ok();
    }
}

fn state(display: &Display) -> State {
    State::from([
        ("available".to_owned(), value(display.available)),
        (
            "autoBrightnessEnabled".to_owned(),
            value(display.auto_brightness),
        ),
        ("rotationLocked".to_owned(), value(display.rotation_locked)),
        (
            "rotationAvailable".to_owned(),
            value(display.rotation_available),
        ),
        (
            "lightSensorAvailable".to_owned(),
            value(display.light_available),
        ),
        ("torchAvailable".to_owned(), value(flashlight::available())),
        ("brightness".to_owned(), value(display.brightness)),
        (
            "nightLightEnabled".to_owned(),
            value(display.night_light_enabled),
        ),
        (
            "nightLightTemperature".to_owned(),
            value(display.night_light_temperature),
        ),
        (
            "nightLightSchedule".to_owned(),
            value(display.night_light_schedule.to_string()),
        ),
        ("nightLightFrom".to_owned(), value(display.night_light_from)),
        ("nightLightTo".to_owned(), value(display.night_light_to)),
        (
            "refreshControls".to_owned(),
            value(display.refresh_controls),
        ),
        (
            "restingRefreshMode".to_owned(),
            value(display.resting_refresh_mode.to_string()),
        ),
        ("autoClear".to_owned(), value(display.auto_clear)),
        (
            "warmLightAvailable".to_owned(),
            value(display.warm_light_available),
        ),
    ])
}

#[derive(Clone)]
struct Display1 {
    qt: cxx_qt::CxxQtThread<Display>,
}

#[zbus::interface(name = "org.marathonos.Shell.Display1")]
impl Display1 {
    async fn get_state(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<State> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| state(&obj)).await
    }

    async fn set_auto_brightness(
        &self,
        enabled: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_auto_brightness(enabled)).await
    }

    async fn set_rotation_lock(
        &self,
        locked: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_rotation_locked(locked)).await
    }

    /// The user's choice, which the curve learns.
    async fn set_brightness(
        &self,
        brightness: f64,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_brightness_from_user(brightness);
        })
        .await
    }

    async fn set_night_light_enabled(
        &self,
        enabled: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_night_light_enabled(enabled)).await
    }

    async fn set_night_light_temperature(
        &self,
        temperature: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_night_light_temperature(temperature.clamp(2700, 6500));
        })
        .await
    }

    async fn set_night_light_schedule(
        &self,
        schedule: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_night_light_schedule(&QString::from(&schedule));
        })
        .await
    }

    /// Minutes after midnight, for the custom schedule.
    async fn set_night_light_times(
        &self,
        from: i32,
        to: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |mut obj| {
            obj.as_mut().set_night_light_from(from);
            obj.set_night_light_to(to);
        })
        .await
    }

    async fn set_screen_state(&self, on: bool, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        let caller = ipc::admit(&h, "Display", &["system"]).await?;
        let reason = format!("D-Bus Display1.SetScreenState from {caller}");
        ipc::on_gui(&self.qt, move |obj| {
            let reason = QString::from(&reason);
            if on {
                obj.turn_screen_on(&reason);
            } else {
                obj.turn_screen_off(&reason);
            }
        })
        .await
    }

    /// quality or text; e-paper only.
    async fn set_resting_refresh_mode(
        &self,
        mode: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_resting_refresh_mode(&QString::from(&mode));
        })
        .await
    }

    async fn set_auto_clear(&self, on: bool, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_auto_clear(on)).await
    }

    /// Clears an e-paper panel's ghosts once the screen is still.
    async fn full_refresh(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Display", &["system"]).await?;
        eink::refresh();
        Ok(())
    }

    /// As the power key does: the lock screen still guards what's behind it.
    async fn wake(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        let caller = ipc::caller(&h)
            .await
            .unwrap_or_else(|| h.sender().map_or_else(String::new, ToString::to_string));
        let reason = format!("D-Bus Display1.Wake from {caller}");
        ipc::on_gui(&self.qt, move |obj| {
            obj.turn_screen_on(&QString::from(&reason));
        })
        .await
    }
}

#[derive(Clone)]
struct Sensor1 {
    qt: cxx_qt::CxxQtThread<Display>,
}

#[zbus::interface(name = "org.marathonos.Shell.Sensor1")]
impl Sensor1 {
    async fn is_available(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        ipc::admit(&h, "Sensor", &["sensors", "system"]).await?;
        ipc::on_gui(&self.qt, |obj| {
            obj.light_available || obj.proximity_available
        })
        .await
    }

    async fn proximity_near(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        ipc::admit(&h, "Sensor", &["sensors", "system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.proximity_near).await
    }

    async fn ambient_light(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<i32> {
        ipc::admit(&h, "Sensor", &["sensors", "system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.ambient_light).await
    }
}

// On the blocking pool: the driver measures while the read waits.
async fn measure(path: PathBuf) -> Option<i32> {
    blocking::unblock(move || read(path)).await
}

#[cfg(test)]
mod tests {
    use super::{
        boot_duty, collapse, front_light, kelvin, start_brightness, warmth, Command, Curve, Panel,
    };
    use crate::night_light::{self, Schedule};

    #[test]
    fn runs_of_levels_collapse_to_their_last() {
        let (tx, rx) = async_channel::unbounded();
        for c in [
            Command::Level(3),
            Command::Sleep,
            Command::Level(5),
            Command::Level(6),
            Command::Wake(1),
            Command::Level(7),
        ] {
            tx.try_send(c).ok();
        }
        let shown: Vec<String> = collapse(Command::Level(2), &rx)
            .iter()
            .map(|c| match c {
                Command::Level(l) => l.to_string(),
                Command::Sleep => "sleep".into(),
                Command::Wake(_) => "wake".into(),
                _ => "other".into(),
            })
            .collect();
        assert_eq!(shown, ["3", "sleep", "6", "wake", "7"]);
    }

    #[test]
    fn a_correction_applies_exactly_where_it_was_made() {
        let mut curve = Curve::default();
        curve.teach(0.9, 50.0);
        assert!((curve.target(50.0) - 0.9).abs() < 1e-9);
        // and relaxes to the base curve away from it.
        assert!((curve.target(5000.0) - super::base(5000.0)).abs() < 0.01);
    }

    #[test]
    fn the_long_term_curve_survives_a_round_trip() {
        let mut curve = Curve::default();
        curve.teach(0.9, 50.0);
        curve.learn();
        let back: Curve = curve.to_string().parse().unwrap_or_default();
        assert_eq!(back.to_string(), curve.to_string());
        assert!(back.long_term.iter().any(|o| *o > 0.0));
    }

    #[test]
    fn warmth_is_the_settings_sliders_over_kelvin() {
        assert_eq!(warmth(4500), 0);
        assert_eq!(warmth(2700), 100);
        assert_eq!(warmth(3400), 61);
        assert_eq!(warmth(6500), 0);
        assert_eq!(kelvin(0), 4500);
        assert_eq!(kelvin(100), 2700);
        assert_eq!(kelvin(50), 3600);
        assert_eq!(kelvin(-5), 4500);
        for w in 0..=100 {
            assert_eq!(warmth(kelvin(w)), w);
        }
        // The Settings app's 100 K steps read back as whole warmths.
        assert_eq!(warmth(4100), 22);
    }

    #[test]
    fn the_warm_leds_take_what_the_white_gives_up() {
        assert_eq!(front_light(0.8, None, 255), (1.0, 0));
        assert_eq!(front_light(0.8, Some(0), 255), (1.0, 0));
        let (white, warm) = front_light(0.8, Some(100), 255);
        assert!(white.abs() < 1e-9);
        assert_eq!(warm, 204);
        let (white, warm) = front_light(0.4, Some(50), 255);
        assert!((white - 0.5).abs() < 1e-9);
        assert_eq!(warm, 51);
        assert_eq!(front_light(0.0, Some(100), 255).1, 0);
    }

    #[test]
    fn a_restart_reads_back_the_light_it_left() {
        let (share, warm) = front_light(0.6, Some(61), 255);
        let white = (0.6 * share * 255.0).round() / 255.0;
        let duty = boot_duty(white, f64::from(warm) / 255.0, true);
        assert!((duty - 0.6).abs() < 0.01, "{duty}");
        // The driver's default-on warm LEDs with the night light off: the
        // white alone is the light.
        assert!((boot_duty(64.0 / 255.0, 1.0, false) - 64.0 / 255.0).abs() < 1e-9);
    }

    #[test]
    fn the_user_level_wins_over_what_the_panel_had() {
        let (tx, _rx) = async_channel::bounded(1);
        let panel = Panel {
            dir: std::path::PathBuf::new(),
            max: 255,
            floor: 0.0,
            dim: 1.0,
            actor: tx,
            white: 1.0,
            warm: None,
        };
        // The driver set 30 behind the shell's back; the user chose 50%.
        let boot = Some((30.0 / 255.0, 0.0));
        let at = start_brightness(&panel, 0.5, boot, false).unwrap_or(0.0);
        assert!((at - 0.5).abs() < 0.01, "{at}");
        // Nothing saved yet: what the panel had.
        let at = start_brightness(&panel, -1.0, boot, false).unwrap_or(0.0);
        assert!((at - 30.0 / 255.0).abs() < 0.01, "{at}");
        assert_eq!(start_brightness(&panel, -1.0, None, false), None);
    }

    #[test]
    fn the_schedule_lights_the_warm_leds_at_night_only() {
        let zone = tz::TimeZone::utc();
        let schedule = Schedule::Times(22 * 60, 7 * 60);
        let lit = |at: i64| {
            let (on, _) = night_light::state(schedule, at, zone.as_ref()).unwrap_or((false, 0));
            front_light(0.5, on.then_some(61), 255).1
        };
        let day = 20_000 * 86_400;
        assert_eq!(lit(day + 23 * 3600), 78);
        assert_eq!(lit(day + 12 * 3600), 0);
    }

    mod rotation {
        use super::super::{follow_rotation, Turn};
        use std::path::Path;
        use std::process::{Child, Command};
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;
        use std::time::Duration;

        struct Daemon(Child);

        impl Drop for Daemon {
            fn drop(&mut self) {
                self.0.kill().ok();
                self.0.wait().ok();
            }
        }

        struct SensorProxy {
            orientation: &'static str,
            claims: Arc<AtomicUsize>,
        }

        #[zbus::interface(name = "net.hadess.SensorProxy")]
        impl SensorProxy {
            fn claim_accelerometer(&self) {
                self.claims.fetch_add(1, Ordering::SeqCst);
            }
            fn release_accelerometer(&self) {}
            #[zbus(property)]
            fn has_accelerometer(&self) -> bool {
                true
            }
            #[zbus(property)]
            fn accelerometer_orientation(&self) -> String {
                self.orientation.to_owned()
            }
        }

        fn found(program: &str) -> bool {
            std::env::var_os("PATH")
                .is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
        }

        fn bus(dir: &Path) -> (Daemon, String) {
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
                std::thread::sleep(Duration::from_millis(20));
            }
            (daemon, address)
        }

        async fn sensor_proxy(
            address: &str,
            orientation: &'static str,
            claims: &Arc<AtomicUsize>,
        ) -> zbus::Connection {
            let proxy = SensorProxy {
                orientation,
                claims: claims.clone(),
            };
            zbus::connection::Builder::address(address)
                .name("net.hadess.SensorProxy")
                .serve_at("/net/hadess/SensorProxy", proxy)
                .build()
                .await
                .unwrap()
        }

        #[test]
        fn a_restarted_sensor_proxy_is_claimed_and_followed_again() {
            if !found("dbus-daemon") {
                return;
            }
            let dir = tempfile::tempdir().unwrap();
            let (_daemon, address) = bus(dir.path());
            async_io::block_on(async {
                let first_claims = Arc::new(AtomicUsize::new(0));
                let first = sensor_proxy(&address, "normal", &first_claims).await;
                let shell = zbus::connection::Builder::address(address.as_str())
                    .build()
                    .await
                    .unwrap();
                let (want, wanted) = async_channel::unbounded();
                let (tx, turns) = async_channel::unbounded();
                let report = move |turn| {
                    tx.try_send(turn).unwrap();
                };
                let next = || async {
                    super::super::io::timeout(Duration::from_secs(10), turns.recv())
                        .await
                        .expect("a turn within 10 s")
                        .unwrap()
                };
                let test = async {
                    assert_eq!(next().await, Turn::Available);
                    want.send(true).await.unwrap();
                    assert_eq!(next().await, Turn::Orientation("portrait"));
                    assert_eq!(first_claims.load(Ordering::SeqCst), 1);

                    drop(first);
                    let second_claims = Arc::new(AtomicUsize::new(0));
                    let _second = sensor_proxy(&address, "bottom-up", &second_claims).await;
                    assert_eq!(next().await, Turn::Available);
                    assert_eq!(next().await, Turn::Orientation("portrait-inverted"));
                    assert_eq!(second_claims.load(Ordering::SeqCst), 1);
                    drop(want);
                };
                futures_lite::future::zip(follow_rotation(&shell, &wanted, &report), test).await;
            });
        }
    }
}
