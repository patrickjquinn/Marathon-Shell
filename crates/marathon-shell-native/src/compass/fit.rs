//! The compass's arithmetic: the heading from gravity and the field, and
//! the calibration that takes the phone's own magnets out of the field.
//! Magnets fixed in the phone add a constant offset (hard iron), and nearby
//! steel stretches the field along each axis (soft iron, taken here as
//! axis-aligned). Readings of the earth's field as the phone turns then lie
//! on an ellipsoid; its centre is the offset and its radii the stretch.

use std::collections::VecDeque;

use serde::{Deserialize, Serialize};

pub type Vector = [f64; 3];

/// Gauss. Readings closer than this to a kept one add nothing to the fit.
const SPACING: f64 = 0.06;
const KEPT: usize = 96;
const FITTED_FROM: usize = 16;
/// The earth's field is 0.22–0.67 G everywhere.
const RADII: std::ops::RangeInclusive<f64> = 0.15..=1.0;
const STRETCH: std::ops::RangeInclusive<f64> = 0.6..=1.6;
/// Relative RMS distance from the fitted sphere.
const WORST_FIT: f64 = 0.06;
/// How far the kept readings' directions spread along every axis, of 2: a
/// phone only turned flat on a table spreads along two.
const SPREAD: f64 = 0.8;
const BETTER: f64 = 0.8;

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct Calibration {
    pub centre: Vector,
    pub scale: Vector,
    /// The field's strength here, in gauss.
    pub radius: f64,
}

impl Calibration {
    pub fn apply(&self, raw: Vector) -> Vector {
        [0, 1, 2].map(|i| (raw[i] - self.centre[i]) * self.scale[i])
    }

    /// How far, relative to the radius, the calibrated readings miss it.
    pub fn error(&self, raw: Vector) -> f64 {
        norm(self.apply(raw)) / self.radius - 1.0
    }

    fn rms(&self, samples: &VecDeque<Vector>) -> f64 {
        let sum: f64 = samples.iter().map(|&s| self.error(s).powi(2)).sum();
        (sum / count(samples)).sqrt()
    }
}

/// Readings spread over the directions the phone has faced, the oldest
/// dropped first.
#[derive(Default)]
pub struct Learner {
    samples: VecDeque<Vector>,
}

impl Learner {
    pub fn add(&mut self, raw: Vector) -> bool {
        if self
            .samples
            .iter()
            .any(|&s| norm(sub(s, raw)) < SPACING)
        {
            return false;
        }
        if self.samples.len() == KEPT {
            self.samples.pop_front();
        }
        self.samples.push_back(raw);
        true
    }

    pub fn clear(&mut self) {
        self.samples.clear();
    }

    /// A calibration from the kept readings, if they cover enough
    /// directions and fit well, and fit clearly better than `current` does.
    pub fn fit(&self, current: Option<&Calibration>) -> Option<Calibration> {
        if self.samples.len() < FITTED_FROM {
            return None;
        }
        let fitted = ellipsoid(&self.samples)?;
        let rms = fitted.rms(&self.samples);
        if rms > WORST_FIT || !spread(&fitted, &self.samples) {
            return None;
        }
        match current {
            // A clearly better fit only, so a moving phone saves seldom.
            Some(c) if c.rms(&self.samples) * BETTER <= rms => None,
            _ => Some(fitted),
        }
    }
}

fn spread(calibration: &Calibration, samples: &VecDeque<Vector>) -> bool {
    (0..3).all(|axis| {
        let along = samples
            .iter()
            .map(|&s| normalised(calibration.apply(s)).map_or(0.0, |u| u[axis]));
        let (low, high) = along.fold((f64::MAX, f64::MIN), |(l, h), v| (l.min(v), h.max(v)));
        high - low >= SPREAD
    })
}

/// The axis-aligned ellipsoid a·x² + b·y² + c·z² + d·x + e·y + f·z = 1
/// through the readings, by least squares about their mean.
fn ellipsoid(samples: &VecDeque<Vector>) -> Option<Calibration> {
    let n = count(samples);
    let mean = [0, 1, 2].map(|i| samples.iter().map(|s| s[i]).sum::<f64>() / n);
    let mut normal = [[0.0; 7]; 6];
    for &s in samples {
        let p = sub(s, mean);
        let row = [p[0] * p[0], p[1] * p[1], p[2] * p[2], p[0], p[1], p[2]];
        for (i, line) in normal.iter_mut().enumerate() {
            for (j, cell) in line.iter_mut().take(6).enumerate() {
                *cell += row[i] * row[j];
            }
            line[6] += row[i];
        }
    }
    let q = solve(normal)?;
    let (square, linear) = ([q[0], q[1], q[2]], [q[3], q[4], q[5]]);
    if square.iter().any(|&a| a <= 0.0) {
        return None;
    }
    let g = 1.0 + (0..3).map(|i| linear[i].powi(2) / (4.0 * square[i])).sum::<f64>();
    let radii = [0, 1, 2].map(|i| (g / square[i]).sqrt());
    let radius = radii.iter().product::<f64>().cbrt();
    let scale = radii.map(|r| radius / r);
    if !RADII.contains(&radius) || !scale.iter().all(|s| STRETCH.contains(s)) {
        return None;
    }
    Some(Calibration {
        centre: [0, 1, 2].map(|i| mean[i] - linear[i] / (2.0 * square[i])),
        scale,
        radius,
    })
}

/// Gaussian elimination with partial pivoting on an augmented 6×7 matrix.
fn solve(mut m: [[f64; 7]; 6]) -> Option<[f64; 6]> {
    for col in 0..6 {
        let pivot = (col..6).max_by(|&a, &b| m[a][col].abs().total_cmp(&m[b][col].abs()))?;
        if m[pivot][col].abs() < 1e-12 {
            return None;
        }
        m.swap(col, pivot);
        let pivot_row = m[col];
        for row in &mut m[col + 1..] {
            let k = row[col] / pivot_row[col];
            for (cell, p) in row.iter_mut().zip(pivot_row).skip(col) {
                *cell -= k * p;
            }
        }
    }
    let mut x = [0.0; 6];
    for row in (0..6).rev() {
        let known: f64 = (row + 1..6).map(|c| m[row][c] * x[c]).sum();
        x[row] = (m[row][6] - known) / m[row][row];
    }
    Some(x)
}

/// Degrees clockwise from magnetic north that the phone points: its top
/// while it lies flat or tilts, its back camera once it stands more than
/// 60° up. `gravity` is the accelerometer's reading (up, at rest) and both
/// are in the device frame: x right, y to the top, z out of the screen.
pub fn heading(gravity: Vector, field: Vector) -> Option<f64> {
    let up = normalised(gravity)?;
    let east = normalised(cross(field, up))?;
    let north = cross(up, east);
    let (e, n) = if up[2].abs() < 0.5 {
        (-east[2], -north[2])
    } else {
        (east[1], north[1])
    };
    Some(e.atan2(n).to_degrees().rem_euclid(360.0))
}

/// Degrees the field points below the horizon.
pub fn dip(gravity: Vector, field: Vector) -> f64 {
    match (normalised(gravity), normalised(field)) {
        (Some(up), Some(f)) => (-(0..3).map(|i| up[i] * f[i]).sum::<f64>()).asin().to_degrees(),
        _ => 0.0,
    }
}

/// At most `KEPT`, so exact as a float.
fn count(samples: &VecDeque<Vector>) -> f64 {
    f64::from(u32::try_from(samples.len()).unwrap_or(u32::MAX))
}

fn sub(a: Vector, b: Vector) -> Vector {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn cross(a: Vector, b: Vector) -> Vector {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn norm(a: Vector) -> f64 {
    a.iter().map(|v| v * v).sum::<f64>().sqrt()
}

fn normalised(a: Vector) -> Option<Vector> {
    let n = norm(a);
    (n > 1e-9).then(|| a.map(|v| v / n))
}

#[cfg(test)]
mod tests {
    use super::{heading, Calibration, Learner, Vector};


    /// Dublin's field: 0.49 G, 67° down, in a frame with y north, z up.
    const EARTH: Vector = [0.0, 0.191, -0.451];
    /// The JP2601's magnet, as its magnetometer reads it.
    const MAGNET: Vector = [2.77, 0.86, -11.72];
    const STRETCH: Vector = [1.08, 0.95, 1.0];

    /// The world turned by yaw about z, then pitch about x, then roll
    /// about y, into the phone's frame.
    fn into_phone(v: Vector, yaw: f64, pitch: f64, roll: f64) -> Vector {
        let (s, c) = yaw.to_radians().sin_cos();
        let v = [c * v[0] - s * v[1], s * v[0] + c * v[1], v[2]];
        let (s, c) = (-pitch).to_radians().sin_cos();
        let v = [v[0], c * v[1] - s * v[2], s * v[1] + c * v[2]];
        let (s, c) = (-roll).to_radians().sin_cos();
        [c * v[0] + s * v[2], v[1], -s * v[0] + c * v[2]]
    }

    fn reading(yaw: f64, pitch: f64, roll: f64) -> Vector {
        let f = into_phone(EARTH, yaw, pitch, roll);
        [0, 1, 2].map(|i| f[i] / STRETCH[i] + MAGNET[i])
    }

    fn up(yaw: f64, pitch: f64, roll: f64) -> Vector {
        into_phone([0.0, 0.0, 9.81], yaw, pitch, roll)
    }

    fn close(a: f64, b: f64, within: f64) -> bool {
        let d = (a - b).rem_euclid(360.0);
        d.min(360.0 - d) <= within
    }

    #[test]
    fn flat_phone_points_its_top() {
        for yaw in [0.0, 37.0, 90.0, 180.0, 271.0] {
            let h = heading(up(yaw, 0.0, 0.0), into_phone(EARTH, yaw, 0.0, 0.0));
            assert!(h.is_some_and(|h| close(h, yaw, 0.01)), "{yaw}: {h:?}");
        }
    }

    #[test]
    fn tilt_does_not_move_the_heading() {
        let h = heading(up(120.0, 25.0, -30.0), into_phone(EARTH, 120.0, 25.0, -30.0));
        assert!(h.is_some_and(|h| close(h, 120.0, 0.01)), "{h:?}");
    }

    #[test]
    fn dublin_dips_down() {
        let d = super::dip(up(40.0, 20.0, 10.0), into_phone(EARTH, 40.0, 20.0, 10.0));
        assert!((d - 67.04).abs() < 0.1, "{d}");
    }

    #[test]
    fn upright_phone_points_its_camera() {
        // Pitched up 80°, its back faces the way its top did.
        let h = heading(up(200.0, 80.0, 0.0), into_phone(EARTH, 200.0, 80.0, 0.0));
        assert!(h.is_some_and(|h| close(h, 200.0, 0.01)), "{h:?}");
    }

    fn figure_eight(learner: &mut Learner) {
        for step in 0..400 {
            let t = f64::from(step) * 0.05;
            learner.add(reading(t * 57.0, 70.0 * (t * 0.7).sin(), 80.0 * (t * 1.3).cos()));
        }
    }

    #[test]
    fn a_figure_eight_learns_the_magnet() {
        let mut learner = Learner::default();
        figure_eight(&mut learner);
        let c = learner.fit(None).expect("a fit");
        for i in 0..3 {
            assert!((c.centre[i] - MAGNET[i]).abs() < 0.002, "{c:?}");
        }
        assert!((c.radius - 0.4898).abs() < 0.03, "{c:?}");
        for (yaw, pitch, roll) in [(0.0, 0.0, 0.0), (75.0, 10.0, 5.0), (300.0, -20.0, 15.0)] {
            let h = heading(up(yaw, pitch, roll), c.apply(reading(yaw, pitch, roll)));
            assert!(h.is_some_and(|h| close(h, yaw, 1.5)), "{yaw}: {h:?}");
        }
    }

    #[test]
    fn the_sensors_noise_barely_moves_the_fit() {
        // About 2 mG on each axis, as the JP2601's part reads lying still.
        let mut seed = 7u32;
        let mut noise = || {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            (f64::from(seed >> 8) / f64::from(1u32 << 24) - 0.5) * 0.007
        };
        let mut learner = Learner::default();
        for step in 0..400 {
            let t = f64::from(step) * 0.05;
            let r = reading(t * 57.0, 70.0 * (t * 0.7).sin(), 80.0 * (t * 1.3).cos());
            learner.add([r[0] + noise(), r[1] + noise(), r[2] + noise()]);
        }
        let c = learner.fit(None).expect("a fit");
        for i in 0..3 {
            assert!((c.centre[i] - MAGNET[i]).abs() < 0.005, "{c:?}");
        }
    }

    #[test]
    fn turning_flat_on_a_table_is_not_enough() {
        let mut learner = Learner::default();
        for yaw in 0..360 {
            learner.add(reading(f64::from(yaw), 0.0, 0.0));
        }
        assert_eq!(learner.fit(None), None);
    }

    #[test]
    fn lying_still_keeps_one_reading() {
        let mut learner = Learner::default();
        for _ in 0..50 {
            learner.add(reading(10.0, 0.0, 0.0));
        }
        assert!(!learner.add(reading(10.0, 0.0, 0.0)));
        assert_eq!(learner.fit(None), None);
    }

    #[test]
    fn a_worse_fit_does_not_replace_a_better_one() {
        let mut learner = Learner::default();
        figure_eight(&mut learner);
        let good = learner.fit(None).expect("a fit");
        let off = Calibration {
            centre: [good.centre[0] + 0.05, good.centre[1], good.centre[2]],
            ..good
        };
        assert_eq!(learner.fit(Some(&good)), None);
        assert!(learner.fit(Some(&off)).is_some());
    }
}
