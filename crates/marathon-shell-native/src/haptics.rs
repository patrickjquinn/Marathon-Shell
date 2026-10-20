//! `Haptics`: the vibration motor. An evdev force-feedback rumble (the
//! Librem 5's pwm-vibrator, most mainline phones) has one effect uploaded at
//! start, retimed and played per buzz; older boards have a sysfs node. Both
//! are driven on the I/O thread.

use std::collections::VecDeque;
use std::path::PathBuf;
use std::pin::Pin;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QVariant};
use evdev::{FFEffect, FFEffectCode, FFEffectData, FFEffectKind, FFReplay};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, enabled, READ, WRITE, NOTIFY)]
        type Haptics = super::HapticsRust;

        #[qinvokable]
        fn vibrate(self: &Haptics, duration: i32);
        /// Milliseconds on, off, on, …
        #[qinvokable]
        #[cxx_name = "vibratePattern"]
        fn vibrate_pattern(self: &Haptics, pattern: &QList_QVariant);
        #[qinvokable]
        #[cxx_name = "cancelVibration"]
        fn cancel_vibration(self: &Haptics);
        #[qinvokable]
        fn light(self: &Haptics);
        #[qinvokable]
        fn medium(self: &Haptics);
        #[qinvokable]
        fn heavy(self: &Haptics);
        /// A gesture crossing its commit point, either way: ngfd's drag_start.
        #[qinvokable]
        fn tick(self: &Haptics);
    }

    impl cxx_qt::Threading for Haptics {}
    impl cxx_qt::Initialize for Haptics {}
}

use qobject::Haptics;

pub struct HapticsRust {
    available: bool,
    enabled: bool,
    motor: Option<Sender<Vec<Step>>>,
}

impl Default for HapticsRust {
    fn default() -> Self {
        Self { available: false, enabled: true, motor: None }
    }
}

const FULL: u16 = 0xFFFF;

/// Plays for `ms` at `magnitude`, or stops with none, then waits `wait` ms.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Step {
    magnitude: Option<u16>,
    ms: u16,
    wait: u16,
}

impl cxx_qt::Initialize for Haptics {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(16);
        let qt = self.qt_thread();
        io::spawn(async move {
            let Some(motor) = blocking::unblock(Motor::find).await else {
                return log::warn("haptics", "no vibrator");
            };
            qt.queue(|mut obj| set!(obj, available, available_changed, true)).ok();
            run(motor, rx).await;
        });
        self.as_mut().rust_mut().motor = Some(tx);
    }
}

impl Haptics {
    fn play(&self, steps: Vec<Step>) {
        if let (true, Some(motor)) = (self.enabled, &self.motor) {
            motor.try_send(steps).ok();
        }
    }

    fn rumble(&self, ms: i32, magnitude: u16) {
        self.play(rumble(ms, magnitude));
    }

    fn vibrate(&self, duration: i32) {
        self.rumble(duration, FULL);
    }

    fn vibrate_pattern(&self, pattern: &QList<QVariant>) {
        self.play(pattern_steps(pattern.iter().filter_map(QVariant::value::<i32>)));
    }

    fn cancel_vibration(&self) {
        if let Some(motor) = &self.motor {
            motor.try_send(Vec::new()).ok();
        }
    }

    fn light(&self) {
        self.rumble(10, FULL);
    }

    fn medium(&self) {
        self.rumble(25, FULL);
    }

    fn heavy(&self) {
        self.rumble(50, FULL);
    }

    fn tick(&self) {
        self.rumble(20, 25_000);
    }
}

fn ms(value: i32) -> u16 {
    u16::try_from(value.max(1)).unwrap_or(u16::MAX)
}

/// One buzz, with a stop after it for motors that don't time themselves.
fn rumble(duration: i32, magnitude: u16) -> Vec<Step> {
    vec![Step { magnitude: Some(magnitude), ms: ms(duration), wait: ms(duration).saturating_add(100) }]
}

fn pattern_steps(pattern: impl Iterator<Item = i32>) -> Vec<Step> {
    let mut steps: Vec<Step> = pattern
        .enumerate()
        .map(|(i, d)| {
            let on = i % 2 == 0;
            Step { magnitude: on.then_some(FULL), ms: if on { ms(d) } else { 0 }, wait: ms(d) }
        })
        .collect();
    if !steps.is_empty() {
        steps.push(Step { magnitude: None, ms: 0, wait: 50 });
    }
    steps
}

enum Motor {
    Rumble(FFEffect),
    /// Writes the duration to start, 0 to stop.
    Sysfs(PathBuf),
}

impl Motor {
    fn find() -> Option<Self> {
        let rumble = evdev::enumerate().find_map(|(_, mut device)| {
            if !device.supported_ff().is_some_and(|ff| ff.contains(FFEffectCode::FF_RUMBLE)) {
                return None;
            }
            device.upload_ff_effect(effect(25, FULL)).ok()
        });
        if let Some(effect) = rumble {
            return Some(Self::Rumble(effect));
        }
        ["/sys/class/leds/vibrator/brightness", "/sys/class/leds/vibrator/activate", "/sys/class/timed_output/vibrator/enable", "/sys/devices/virtual/timed_output/vibrator/enable"]
            .into_iter()
            .map(PathBuf::from)
            .find(|p| p.exists())
            .map(Self::Sysfs)
    }

    fn play(&mut self, ms: u16, magnitude: u16) {
        let played = match self {
            Self::Rumble(e) => e.update(effect(ms, magnitude)).and_then(|()| e.play(1)),
            Self::Sysfs(path) => std::fs::write(path, ms.to_string()),
        };
        if let Err(e) = played {
            log::warn("haptics", e);
        }
    }

    fn stop(&mut self) {
        let stopped = match self {
            Self::Rumble(e) => e.stop(),
            Self::Sysfs(path) => std::fs::write(path, "0"),
        };
        if let Err(e) = stopped {
            log::warn("haptics", e);
        }
    }
}

fn effect(ms: u16, magnitude: u16) -> FFEffectData {
    FFEffectData {
        direction: 0,
        trigger: evdev::FFTrigger::default(),
        replay: FFReplay { length: ms, delay: 0 },
        kind: FFEffectKind::Rumble { strong_magnitude: magnitude, weak_magnitude: magnitude },
    }
}

/// Plays each request's steps until a newer one replaces them, then stops.
async fn run(mut motor: Motor, requests: Receiver<Vec<Step>>) {
    let mut steps: VecDeque<Step> = VecDeque::new();
    let mut wait = None;
    loop {
        match io::recv_within(&requests, wait).await {
            Some(Err(_)) => return,
            Some(Ok(new)) => {
                if new.is_empty() {
                    motor.stop();
                }
                steps = new.into();
            }
            None => {}
        }
        match steps.pop_front() {
            Some(step) => {
                match step.magnitude {
                    Some(m) => motor.play(step.ms, m),
                    None => motor.stop(),
                }
                wait = Some(Duration::from_millis(step.wait.into()));
            }
            None => {
                if wait.take().is_some() {
                    motor.stop();
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{pattern_steps, rumble, Step, FULL};

    #[test]
    fn a_pattern_alternates_on_and_off_then_rests() {
        let on = |ms| Step { magnitude: Some(FULL), ms, wait: ms };
        let off = |wait| Step { magnitude: None, ms: 0, wait };
        assert_eq!(pattern_steps([500, 500, 200].into_iter()), [on(500), off(500), on(200), off(50)]);
        assert_eq!(pattern_steps(std::iter::empty()), []);
        assert_eq!(rumble(25, 100), [Step { magnitude: Some(100), ms: 25, wait: 125 }]);
    }
}
