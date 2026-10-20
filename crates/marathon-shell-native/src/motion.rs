//! `ActivityService`: the Activity Rings. The accelerometer's IIO sysfs
//! values, read at 50 Hz on the I/O thread, feed the vendored Oxford step
//! counter (thirdparty/oxford-step-counter). Move is steps against 6,500;
//! Exercise, minutes of at least 100 steps against 30; Stand, hours with a
//! minute of at least 30 steps against 12. `MARATHON_MOTION_DEMO=1`
//! synthesizes a brisk walk instead.

use std::fs::File;
use std::os::unix::fs::FileExt;
use std::path::PathBuf;
use std::pin::Pin;
use std::time::{Duration, Instant};

use async_io::Timer;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};

use crate::{clock, io, log};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, CONSTANT)]
        #[qproperty(i32, steps_today, cxx_name = "stepsToday", READ, NOTIFY = rings_changed)]
        #[qproperty(f64, move_percent, cxx_name = "movePercent", READ, NOTIFY = rings_changed)]
        #[qproperty(f64, exercise_percent, cxx_name = "exercisePercent", READ, NOTIFY = rings_changed)]
        #[qproperty(f64, stand_percent, cxx_name = "standPercent", READ, NOTIFY = rings_changed)]
        type ActivityService = super::ActivityServiceRust;

        #[qsignal]
        #[cxx_name = "ringsChanged"]
        fn rings_changed(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for ActivityService {}
    impl cxx_qt::Initialize for ActivityService {}
}

use qobject::ActivityService;

mod oxford {
    unsafe extern "C" {
        pub fn initAlgo();
        pub fn processSample(time: i32, x: i16, y: i16, z: i16);
        pub fn resetSteps();
        pub fn getSteps() -> u16;
    }
}

const SAMPLE: Duration = Duration::from_millis(20);
// While iio-sensor-proxy holds the buffer, direct reads fail with EBUSY.
const RETRY: Duration = Duration::from_secs(1);
const MINUTE: Duration = Duration::from_mins(1);
const MOVE_GOAL: f64 = 6500.0;
const EXERCISE_GOAL: f64 = 30.0;
const STAND_GOAL: f64 = 12.0;

enum Source {
    Demo,
    Iio(PathBuf),
}

pub struct ActivityServiceRust {
    available: bool,
    steps_today: i32,
    move_percent: f64,
    exercise_percent: f64,
    stand_percent: f64,
    source: Option<Source>,
}

impl Default for ActivityServiceRust {
    fn default() -> Self {
        let source = if std::env::var("MARATHON_MOTION_DEMO").is_ok_and(|v| v != "0" && !v.is_empty()) {
            Some(Source::Demo)
        } else {
            accelerometer().map(Source::Iio)
        };
        Self { available: source.is_some(), steps_today: 0, move_percent: 0.0, exercise_percent: 0.0, stand_percent: 0.0, source }
    }
}

/// The first IIO device with all three raw axes.
fn accelerometer() -> Option<PathBuf> {
    let mut devices: Vec<PathBuf> = std::fs::read_dir("/sys/bus/iio/devices").ok()?.flatten().map(|e| e.path()).collect();
    devices.sort();
    devices.into_iter().find(|d| ["x", "y", "z"].iter().all(|a| d.join(format!("in_accel_{a}_raw")).exists()))
}

impl cxx_qt::Initialize for ActivityService {
    fn initialize(mut self: Pin<&mut Self>) {
        let Some(source) = self.as_mut().rust_mut().source.take() else {
            return log::warn("motion", "no IIO accelerometer; MARATHON_MOTION_DEMO=1 shows the rings");
        };
        io::spawn(sample(self.qt_thread(), source));
    }
}

/// A day's rings so far.
#[derive(Default)]
struct Rings {
    day: i32,
    at_last_minute: i32,
    active_minutes: i32,
    stood: [bool; 24],
}

impl Rings {
    /// A minute passed with `steps` today; false when it starts a new day,
    /// whose count starts again.
    fn minute(&mut self, steps: i32, day: i32, hour: usize) -> bool {
        if day != self.day {
            *self = Rings { day, ..Rings::default() };
            return false;
        }
        let delta = (steps - self.at_last_minute).max(0);
        self.at_last_minute = steps;
        if delta >= 100 {
            self.active_minutes += 1;
        }
        if delta >= 30 {
            if let Some(stood) = self.stood.get_mut(hour) {
                *stood = true;
            }
        }
        true
    }

    fn stand_hours(&self) -> i32 {
        self.stood.iter().map(|&s| i32::from(s)).sum()
    }
}

fn steps(base: i32) -> i32 {
    // SAFETY: only the sampling task calls the algorithm.
    base + i32::from(unsafe { oxford::getSteps() })
}

fn today() -> (i32, usize) {
    clock::local(clock::now()).map_or((0, 0), |tm| (tm.tm_year * 1000 + tm.tm_yday, usize::try_from(tm.tm_hour).unwrap_or(0)))
}

fn axis(file: &File) -> Option<i16> {
    let mut buf = [0; 16];
    let n = file.read_at(&mut buf, 0).ok()?;
    std::str::from_utf8(buf.get(..n)?).ok()?.trim().parse::<i32>().ok().map(|v| i16::try_from(v).unwrap_or(if v < 0 { i16::MIN } else { i16::MAX }))
}

/// A brisk walk: about 100 steps a minute, peak to peak over the
/// algorithm's motion threshold.
#[allow(clippy::cast_possible_truncation, reason = "a few hundred mg")]
fn demo(ms: u128) -> [i16; 3] {
    #[allow(clippy::cast_precision_loss, reason = "a phase")]
    let phase = ms as f64 / 100.0;
    [(300.0 * (phase * 0.5).sin()) as i16, (250.0 * (phase * 0.5).cos()) as i16, (-980.0 + 600.0 * phase.sin()) as i16]
}

async fn sample(qt: CxxQtThread<ActivityService>, source: Source) {
    let axes = match &source {
        Source::Demo => None,
        Source::Iio(dir) => match ["x", "y", "z"].map(|a| File::open(dir.join(format!("in_accel_{a}_raw")))) {
            [Ok(x), Ok(y), Ok(z)] => Some([x, y, z]),
            _ => return log::warn("motion", format_args!("cannot open {}", dir.display())),
        },
    };
    // SAFETY: the algorithm's state is global; only this task touches it.
    unsafe { oxford::initAlgo() };
    let mut started = Instant::now();
    let mut minute = Instant::now();
    let mut base = 0;
    let (day, _) = today();
    let mut rings = Rings { day, ..Rings::default() };
    let mut shown = (-1, -1, -1);
    loop {
        let elapsed = started.elapsed().as_millis();
        let sample = match &axes {
            None => Some(demo(elapsed)),
            Some([x, y, z]) => axis(x).zip(axis(y)).zip(axis(z)).map(|((x, y), z)| [x, y, z]),
        };
        if let Some([x, y, z]) = sample {
            if let Ok(ms) = i32::try_from(elapsed) {
                // SAFETY: as above.
                unsafe { oxford::processSample(ms, x, y, z) };
            } else {
                // The algorithm's clock would roll over, about every 24 days.
                base = steps(base);
                // SAFETY: as above.
                unsafe { oxford::initAlgo() };
                started = Instant::now();
            }
        }
        if minute.elapsed() >= MINUTE {
            minute = Instant::now();
            let (day, hour) = today();
            if !rings.minute(steps(base), day, hour) {
                base = 0;
                // SAFETY: as above.
                unsafe { oxford::resetSteps() };
            }
        }
        let now = (steps(base), rings.active_minutes, rings.stand_hours());
        if now != shown {
            shown = now;
            qt.queue(move |mut obj| {
                let (steps, active, stand) = now;
                let mut rust = obj.as_mut().rust_mut();
                rust.steps_today = steps;
                rust.move_percent = (f64::from(steps) / MOVE_GOAL).min(1.0);
                rust.exercise_percent = (f64::from(active) / EXERCISE_GOAL).min(1.0);
                rust.stand_percent = (f64::from(stand) / STAND_GOAL).min(1.0);
                obj.rings_changed();
            })
            .ok();
        }
        Timer::after(if sample.is_some() { SAMPLE } else { RETRY }).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_new_day_starts_the_rings_again() {
        let mut rings = Rings { day: 1, ..Rings::default() };
        assert!(rings.minute(120, 1, 9));
        assert!(rings.minute(160, 1, 9));
        assert_eq!((rings.active_minutes, rings.stand_hours()), (1, 1));
        assert!(!rings.minute(200, 2, 0));
        assert_eq!((rings.active_minutes, rings.stand_hours(), rings.at_last_minute), (0, 0, 0));
    }
}
