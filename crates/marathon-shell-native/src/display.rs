//! The display: the backlight and the adaptive curve that sets it, whether
//! the screen is on, and the ambient light and proximity sensors. Sysfs I/O
//! runs on the I/O thread: a DCS or I2C backlight can take milliseconds a
//! write, and a vcnl4000-class sensor measures while its read waits. The one
//! exception is the doze blank, which must land before the CRTC goes off.

use std::collections::VecDeque;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::str::FromStr;
use std::time::{Duration, Instant};

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::io::{self, read};
use crate::log;

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
        #[qproperty(bool, proximity_available, cxx_name = "proximityAvailable", READ, CONSTANT)]
        #[qproperty(f64, brightness, READ, NOTIFY)]
        #[qproperty(bool, auto_brightness, cxx_name = "autoBrightness", READ, WRITE = set_auto_brightness, NOTIFY)]
        #[qproperty(bool, rotation_locked, cxx_name = "rotationLocked", READ, WRITE, NOTIFY)]
        #[qproperty(bool, night_light_enabled, cxx_name = "nightLightEnabled", READ, WRITE, NOTIFY)]
        #[qproperty(i32, night_light_temperature, cxx_name = "nightLightTemperature", READ, WRITE, NOTIFY)]
        #[qproperty(QString, night_light_schedule, cxx_name = "nightLightSchedule", READ, WRITE, NOTIFY)]
        /// What the user taught the brightness curve, as the settings keep it.
        #[qproperty(QString, learned_curve, cxx_name = "learnedCurve", READ, WRITE = set_learned_curve, NOTIFY)]
        /// The one record of whether the screen is on.
        #[qproperty(bool, screen_on, cxx_name = "screenOn", READ, NOTIFY)]
        #[qproperty(bool, proximity_near, cxx_name = "proximityNear", READ, NOTIFY)]
        #[qproperty(i32, ambient_light, cxx_name = "ambientLight", READ, NOTIFY)]
        type Display = super::DisplayRust;

        /// Every turn on or off, so the compositor re-asserts the panel's
        /// power even when the state is unchanged.
        #[qsignal]
        #[cxx_name = "screenStateChanged"]
        fn screen_state_changed(self: Pin<&mut Self>, on: bool);

        #[cxx_name = "setAutoBrightness"]
        fn set_auto_brightness(self: Pin<&mut Display>, enabled: bool);
        #[cxx_name = "setLearnedCurve"]
        fn set_learned_curve(self: Pin<&mut Display>, curve: &QString);

        /// The backlight under `backlight_dir`, the iio sensors under
        /// `iio_dir`, and the lowest duty the panel is visible at.
        #[qinvokable]
        fn start(self: Pin<&mut Display>, backlight_dir: &QString, iio_dir: &QString, floor: f64);
        #[qinvokable]
        #[cxx_name = "setBrightness"]
        fn set_brightness(self: Pin<&mut Display>, brightness: f64);
        /// A brightness the user chose, which the curve learns.
        #[qinvokable]
        #[cxx_name = "setBrightnessFromUser"]
        fn set_brightness_from_user(self: Pin<&mut Display>, brightness: f64);
        #[qinvokable]
        #[cxx_name = "turnScreenOn"]
        fn turn_screen_on(self: Pin<&mut Display>);
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
    }

    impl cxx_qt::Threading for Display {}
}

use qobject::Display;

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct DisplayRust {
    available: bool,
    light_available: bool,
    proximity_available: bool,
    brightness: f64,
    auto_brightness: bool,
    rotation_locked: bool,
    night_light_enabled: bool,
    night_light_temperature: i32,
    night_light_schedule: QString,
    learned_curve: QString,
    screen_on: bool,
    proximity_near: bool,
    ambient_light: i32,
    panel: Option<Panel>,
    sensors: Option<Sender<(bool, bool)>>,
    proximity_wanted: bool,
    proximity_blanked: bool,
    curve: Curve,
    smoothed_lux: Option<f64>,
    /// Since when the target has stayed brighter (true) or dimmer.
    dwell: Option<(bool, Instant)>,
    manual_at: Option<Instant>,
    lessons: u64,
}

impl Default for DisplayRust {
    fn default() -> Self {
        Self {
            available: false,
            light_available: false,
            proximity_available: false,
            brightness: 0.5,
            auto_brightness: false,
            rotation_locked: false,
            night_light_enabled: false,
            night_light_temperature: 3400,
            night_light_schedule: QString::from("off"),
            learned_curve: QString::default(),
            screen_on: true,
            proximity_near: false,
            ambient_light: 500,
            panel: None,
            sensors: None,
            proximity_wanted: false,
            proximity_blanked: false,
            curve: Curve::default(),
            smoothed_lux: None,
            dwell: None,
            manual_at: None,
            lessons: 0,
        }
    }
}

/// The backlight as the user sees it: their 0..1 runs from the panel's
/// visible floor to full duty, on the nearest of its levels.
struct Panel {
    dir: PathBuf,
    max: i32,
    floor: f64,
    actor: Sender<Command>,
}

impl Panel {
    #[allow(clippy::cast_possible_truncation, reason = "at most max_brightness")]
    fn level(&self, user: f64) -> i32 {
        let duty = self.floor + (1.0 - self.floor) * user.clamp(0.0, 1.0);
        ((duty * f64::from(self.max)).round() as i32).clamp(1, self.max)
    }

    fn user(&self, level: i32) -> f64 {
        ((f64::from(level) / f64::from(self.max) - self.floor) / (1.0 - self.floor)).clamp(0.0, 1.0)
    }

    fn send(&self, command: Command) {
        if self.actor.try_send(command).is_err() {
            log::warn("display", "backlight busy; dropped a write");
        }
    }
}

impl Display {
    fn start(mut self: Pin<&mut Self>, backlight_dir: &QString, iio_dir: &QString, floor: f64) {
        if let Some((dir, max, level)) = find_backlight(Path::new(&backlight_dir.to_string())) {
            let (tx, rx) = async_channel::bounded(64);
            io::spawn(backlight(dir.clone(), rx));
            let panel = Panel { dir, max, floor, actor: tx };
            let mut rust = self.as_mut().rust_mut();
            rust.brightness = level.map_or(0.5, |l| panel.user(l));
            rust.available = true;
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
    }

    fn set_brightness(mut self: Pin<&mut Self>, brightness: f64) {
        let Some(panel) = &self.panel else { return };
        let level = panel.level(brightness);
        let shown = panel.user(level);
        panel.send(Command::Level(level));
        let mut rust = self.as_mut().rust_mut();
        // The user's level wins over auto-brightness for a while.
        rust.manual_at = Some(Instant::now());
        rust.brightness = shown;
        self.brightness_changed();
    }

    fn set_brightness_from_user(mut self: Pin<&mut Self>, brightness: f64) {
        self.as_mut().set_brightness(brightness);
        if !self.auto_brightness {
            return;
        }
        let lux = self.smoothed_lux.unwrap_or_else(|| f64::from(self.ambient_light));
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

    fn set_auto_brightness(mut self: Pin<&mut Self>, enabled: bool) {
        // Off, and not settable, without a light sensor.
        set!(self, auto_brightness, auto_brightness_changed, enabled && self.light_available);
        self.want_sensors();
    }

    fn lux(mut self: Pin<&mut Self>, lux: i32) {
        set!(self, ambient_light, ambient_light_changed, lux);
        if !self.auto_brightness || self.manual_at.is_some_and(|t| t.elapsed() < Duration::from_secs(5)) {
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
        self.as_mut().rust_mut().brightness = target;
        self.brightness_changed();
    }

    fn turn_screen_on(self: Pin<&mut Self>) {
        self.set_screen(true);
    }

    fn turn_screen_off(self: Pin<&mut Self>, reason: &QString) {
        log::warn("display", format_args!("screen off by {reason}"));
        self.set_screen(false);
    }

    fn force_screen_on(mut self: Pin<&mut Self>) {
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
        if let (false, Some(panel)) = (on, &self.panel) {
            if let Err(e) = fs::write(panel.dir.join("bl_power"), "4\n") {
                log::warn("display", format_args!("bl_power: {e}"));
            }
            panel.send(Command::Sleep);
        }
        set!(self, screen_on, screen_on_changed, on);
        self.as_mut().screen_state_changed(on);
        if let (true, Some(panel)) = (on, &self.panel) {
            panel.send(Command::Wake(panel.level(self.brightness)));
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
    }

    fn set_proximity_wanted(mut self: Pin<&mut Self>, wanted: bool) {
        self.as_mut().rust_mut().proximity_wanted = wanted;
        // A stale "near" must not outlive the call.
        if !wanted {
            set!(self, proximity_near, proximity_near_changed, false);
        }
        self.want_sensors();
    }

    /// Light while auto-brightness has a lit screen to set; proximity while
    /// a call wants it.
    fn want_sensors(&self) {
        if let Some(sensors) = &self.sensors {
            sensors.try_send((self.auto_brightness && self.screen_on, self.proximity_wanted)).ok();
        }
    }
}

/// The panel's backlight, its `max_brightness` and its level now.
fn find_backlight(root: &Path) -> Option<(PathBuf, i32, Option<i32>)> {
    let mut names: Vec<_> = fs::read_dir(root).ok()?.flatten().map(|e| e.file_name()).collect();
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
        .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("iio:device")))
        .collect();
    dirs.sort();
    let dir = dirs.into_iter().find(|d| d.join("in_illuminance_raw").exists())?;
    Some(Channels {
        light: dir.join("in_illuminance_raw"),
        lux_scale: read(dir.join("in_illuminance_scale")).filter(|s| *s > 0.0).unwrap_or(1.0),
        proximity: Some(dir.join("in_proximity_raw")).filter(|p| p.exists()),
        near_level: read(dir.join("in_proximity_nearlevel")).filter(|l| *l > 0).unwrap_or(16),
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
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss, clippy::cast_precision_loss, reason = "0 to 8")]
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
        let Some((ll, offset)) = self.short_term else { return };
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
        for (o, v) in curve.long_term.iter_mut().zip(s.split(',').filter(|v| !v.is_empty())) {
            *o = v.trim().parse::<f64>()?.clamp(-0.4, 0.4);
        }
        Ok(curve)
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
                    log::warn("display", "the panel is still dark after a wake; lighting it again");
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
        let name = self.dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let session = SessionProxy::new(&io::system_bus().await?).await?;
        session.set_brightness("backlight", &name, u32::try_from(level).unwrap_or(0)).await
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
async fn sensors(qt: cxx_qt::CxxQtThread<Display>, channels: Channels, wanted: Receiver<(bool, bool)>) {
    let (mut light, mut proximity) = (false, false);
    let (mut last_lux, mut last_near) = (None, None);
    loop {
        let every = (light || proximity).then(|| Duration::from_millis(if proximity { 200 } else { 1000 }));
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
                qt.queue(move |mut obj| set!(obj, proximity_near, proximity_near_changed, near)).ok();
            }
        }
    }
}

// On the blocking pool: the driver measures while the read waits.
async fn measure(path: PathBuf) -> Option<i32> {
    blocking::unblock(move || read(path)).await
}

#[cfg(test)]
mod tests {
    use super::{collapse, Command, Curve};

    #[test]
    fn runs_of_levels_collapse_to_their_last() {
        let (tx, rx) = async_channel::unbounded();
        for c in [Command::Level(3), Command::Sleep, Command::Level(5), Command::Level(6), Command::Wake(1), Command::Level(7)] {
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
}
