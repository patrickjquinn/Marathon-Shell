//! The compass: the IIO magnetometer, tilt-compensated by the accelerometer
//! and calibrated for the phone's own magnets. It reads only while an app
//! holds it (`Sensor1.StartCompass`) and the screen is on. The calibration
//! is learnt from the readings whenever the phone moves, kept in
//! `$XDG_STATE_HOME/marathon/compass.json`, and replaced once the field
//! stops fitting it, as when a magnet comes close.

mod fit;

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::Duration;

use async_channel::Sender;
use async_io::Timer;
use futures_lite::{future, StreamExt};

use crate::io::{self, read};
use crate::{ipc, log, stored};
use fit::{Calibration, Learner, Vector};

const PERIOD: Duration = Duration::from_millis(100);
const STATE: &str = "compass.json";
/// The calibrated field may miss its radius by this share, on average,
/// before the calibration is taken as stale.
const STALE: f64 = 0.15;
/// The weight of a new reading in that average, and in the heading's.
const SMOOTHING: f64 = 0.3;
const AVERAGING: f64 = 0.05;

static ASKS: OnceLock<Sender<Ask>> = OnceLock::new();

pub(crate) enum Ask {
    Hold(String),
    Release(String),
    Left(String),
    Screen(bool),
}

/// An IIO device's three axes of one kind, in the device frame.
struct Axes {
    files: [PathBuf; 3],
    offset: f64,
    scale: f64,
    matrix: [Vector; 3],
}

impl Axes {
    fn find(root: &Path, kind: &str) -> Option<Self> {
        let mut dirs: Vec<PathBuf> = std::fs::read_dir(root)
            .ok()?
            .flatten()
            .map(|e| e.path())
            .collect();
        dirs.sort();
        let dir = dirs
            .into_iter()
            .find(|d| d.join(format!("in_{kind}_x_raw")).exists())?;
        let matrix = ["mount_matrix", "in_mount_matrix", &format!("in_{kind}_mount_matrix")]
            .iter()
            .find_map(|name| matrix(&std::fs::read_to_string(dir.join(name)).ok()?))
            .unwrap_or([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]);
        Some(Self {
            files: ["x", "y", "z"].map(|a| dir.join(format!("in_{kind}_{a}_raw"))),
            offset: read(dir.join(format!("in_{kind}_offset"))).unwrap_or(0.0),
            scale: read(dir.join(format!("in_{kind}_scale")))?,
            matrix,
        })
    }

    /// Each read starts a measurement and waits for it.
    fn read(&self) -> Option<Vector> {
        let mut raw = [0.0; 3];
        for (value, file) in raw.iter_mut().zip(&self.files) {
            *value = (read::<f64>(file)? + self.offset) * self.scale;
        }
        Some(self.matrix.map(|row| (0..3).map(|i| row[i] * raw[i]).sum()))
    }
}

/// An IIO `mount_matrix`: "a, b, c; d, e, f; g, h, i", rows first.
fn matrix(text: &str) -> Option<[Vector; 3]> {
    let rows: Vec<Vec<f64>> = text
        .trim()
        .split(';')
        .map(|row| row.split(',').map(|v| v.trim().parse().ok()).collect())
        .collect::<Option<_>>()?;
    let row = |i: usize| -> Option<Vector> { rows.get(i)?.as_slice().try_into().ok() };
    Some([row(0)?, row(1)?, row(2)?])
}

/// Starts the compass if the phone has a magnetometer and an accelerometer.
pub(crate) fn start(root: &Path) {
    let (Some(field), Some(gravity)) = (Axes::find(root, "magn"), Axes::find(root, "accel")) else {
        return;
    };
    let (tx, rx) = async_channel::bounded(16);
    if ASKS.set(tx).is_err() {
        return;
    }
    let (left, gone) = async_channel::bounded(16);
    io::each_session_bus(move |session| crate::location::follow_left(session, left.clone()));
    io::spawn(async move {
        let asks = rx.or(gone.map(Ask::Left));
        run(field, gravity, asks).await;
    });
}

pub(crate) fn available() -> bool {
    ASKS.get().is_some()
}

pub(crate) async fn ask(ask: Ask) {
    if let Some(asks) = ASKS.get() {
        asks.send(ask).await.ok();
    }
}

pub(crate) fn screen(on: bool) {
    if let Some(asks) = ASKS.get() {
        asks.try_send(Ask::Screen(on)).ok();
    }
}

enum Event {
    Ask(Ask),
    Tick,
}

struct Reading {
    calibration: Option<Calibration>,
    learner: Learner,
    /// The calibrated field's average miss.
    miss: f64,
    /// The smoothed heading as a unit vector, east and north.
    smoothed: Option<(f64, f64)>,
    sent: Option<(i32, bool)>,
}

async fn run(field: Axes, gravity: Axes, asks: impl futures_lite::Stream<Item = Ask>) {
    let mut asks = std::pin::pin!(asks);
    let mut holders: HashSet<String> = HashSet::new();
    let mut screen_on = true;
    let mut state = Reading {
        calibration: stored::load(STATE),
        learner: Learner::default(),
        miss: 0.0,
        smoothed: None,
        sent: None,
    };
    let sensors = std::sync::Arc::new((field, gravity));
    loop {
        let reading = !holders.is_empty() && screen_on;
        let event = if reading {
            future::or(
                async { asks.next().await.map(Event::Ask) },
                async {
                    Timer::after(PERIOD).await;
                    Some(Event::Tick)
                },
            )
            .await
        } else {
            asks.next().await.map(Event::Ask)
        };
        match event {
            None => return,
            Some(Event::Ask(Ask::Hold(name))) => {
                // A new holder hears the heading as it is.
                state.sent = None;
                holders.insert(name);
            }
            Some(Event::Ask(Ask::Release(name) | Ask::Left(name))) => {
                holders.remove(&name);
            }
            Some(Event::Ask(Ask::Screen(on))) => screen_on = on,
            Some(Event::Tick) => {
                let sensors = std::sync::Arc::clone(&sensors);
                let sample = blocking::unblock(move || Some((sensors.0.read()?, sensors.1.read()?)));
                if let Some((raw, up)) = sample.await {
                    state.take(raw, up);
                }
            }
        }
        if (holders.is_empty() || !screen_on) && reading {
            state.smoothed = None;
            state.sent = None;
        }
    }
}

impl Reading {
    fn take(&mut self, raw: Vector, up: Vector) {
        if self.learner.add(raw) {
            if let Some(better) = self.learner.fit(self.calibration.as_ref()) {
                // Dips about 67° down in Ireland: a frame that dips up has the
                // magnetometer's mount matrix wrong.
                log::warn(
                    "compass",
                    format_args!(
                        "calibrated: {:.2} G, dipping {:.0}° down, offset {:?}",
                        better.radius,
                        fit::dip(up, better.apply(raw)),
                        better.centre
                    ),
                );
                self.calibration = Some(better);
                self.miss = 0.0;
                if let Err(e) = stored::save(STATE, &better) {
                    log::warn("compass", format_args!("{e}"));
                }
            }
        }
        let Some(calibration) = self.calibration else {
            return self.send(-1.0, false);
        };
        let was_fresh = self.miss < STALE;
        self.miss += AVERAGING * (calibration.error(raw).abs() - self.miss);
        let fresh = self.miss < STALE;
        // The field changed under the old readings too.
        if was_fresh && !fresh {
            self.learner.clear();
        }
        let Some(degrees) = fit::heading(up, calibration.apply(raw)) else {
            return;
        };
        let (e, n) = degrees.to_radians().sin_cos();
        let (se, sn) = self.smoothed.map_or((e, n), |(se, sn)| {
            (se + SMOOTHING * (e - se), sn + SMOOTHING * (n - sn))
        });
        self.smoothed = Some((se, sn));
        self.send(se.atan2(sn).to_degrees().rem_euclid(360.0), fresh);
    }

    /// Only whole-degree changes go on the bus.
    fn send(&mut self, heading: f64, calibrated: bool) {
        #[allow(clippy::cast_possible_truncation, reason = "a heading in degrees")]
        let shown = (heading.round() as i32, calibrated);
        if self.sent != Some(shown) {
            self.sent = Some(shown);
            ipc::signal("Sensor", "HeadingChanged", (heading, calibrated));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::matrix;

    #[test]
    fn reads_an_iio_mount_matrix() {
        assert_eq!(
            matrix("0, -1, 0; 1, 0, 0; 0, 0, 1\n"),
            Some([[0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])
        );
        assert_eq!(matrix("1, 0; 0, 1"), None);
    }
}
