//! GLONASS broadcast ephemeris: PZ-90 state vector propagated with RK4
//! (GLONASS ICD 2008, A.3.1.2), close enough to WGS-84 for single-point use.

use nalgebra::Vector3;

const GM: f64 = 398_600.441_8e9;
const AE: f64 = 6_378_136.0;
const J2: f64 = 1_082_625.75e-9;
const OMEGA: f64 = 7.292_115e-5;
const STEP: f64 = 60.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Ephemeris {
    /// Reference time, GPS seconds of week.
    pub tb: f64,
    /// Satellite clock offset at `tb` (-TauN) and its rate (GammaN).
    pub clock: f64,
    pub gamma: f64,
    pub pos: Vector3<f64>,
    pub vel: Vector3<f64>,
    /// Lunisolar acceleration.
    pub acc: Vector3<f64>,
    /// Frequency channel, -7..6.
    pub k: i8,
    pub health: u8,
}

impl Ephemeris {
    /// L1 carrier frequency of this satellite.
    pub fn carrier(&self) -> f64 {
        1602e6 + f64::from(self.k) * 0.5625e6
    }
}

#[allow(clippy::many_single_char_names, reason = "ICD symbols")]
fn deriv(p: Vector3<f64>, v: Vector3<f64>, acc: Vector3<f64>) -> (Vector3<f64>, Vector3<f64>) {
    let r2 = p.norm_squared();
    let r = r2.sqrt();
    let c = 1.5 * J2 * GM * AE * AE / (r2 * r2 * r);
    let zz = 5.0 * p.z * p.z / r2;
    let a = Vector3::new(
        -GM * p.x / (r2 * r) - c * p.x * (1.0 - zz) + OMEGA * OMEGA * p.x + 2.0 * OMEGA * v.y,
        -GM * p.y / (r2 * r) - c * p.y * (1.0 - zz) + OMEGA * OMEGA * p.y - 2.0 * OMEGA * v.x,
        -GM * p.z / (r2 * r) - c * p.z * (3.0 - zz),
    ) + acc;
    (v, a)
}

/// ECEF position and clock offset at GPS time of week `t`.
#[allow(clippy::many_single_char_names, reason = "RK4 symbols")]
pub fn position(e: &Ephemeris, t: f64) -> (Vector3<f64>, f64) {
    let total = crate::orbit::dt(t, e.tb);
    let (mut p, mut v) = (e.pos, e.vel);
    let mut done = 0.0;
    while (total - done).abs() > 1e-9 {
        let h = (total - done).clamp(-STEP, STEP);
        let (k1p, k1v) = deriv(p, v, e.acc);
        let (k2p, k2v) = deriv(p + k1p * (h / 2.0), v + k1v * (h / 2.0), e.acc);
        let (k3p, k3v) = deriv(p + k2p * (h / 2.0), v + k2v * (h / 2.0), e.acc);
        let (k4p, k4v) = deriv(p + k3p * h, v + k3v * h, e.acc);
        p += (k1p + k2p * 2.0 + k3p * 2.0 + k4p) * (h / 6.0);
        v += (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (h / 6.0);
        done += h;
    }
    (p, e.clock + e.gamma * total)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn circular_orbit_keeps_radius() {
        // Equatorial orbit: the inertial circular speed less the frame rotation.
        let r = 25_500_000.0;
        let vi = (GM / r).sqrt();
        let e = Ephemeris {
            tb: 1000.0,
            clock: 1e-5,
            gamma: 1e-12,
            pos: Vector3::new(r, 0.0, 0.0),
            vel: Vector3::new(0.0, vi - OMEGA * r, 0.0),
            acc: Vector3::zeros(),
            k: 1,
            health: 0,
        };
        let (p, clk) = position(&e, 1000.0 + 1800.0);
        // J2 perturbs an equatorial orbit by tens of metres in half an hour.
        assert!((p.norm() - r).abs() < 2000.0, "{}", p.norm() - r);
        assert!((clk - (1e-5 + 1800e-12)).abs() < 1e-15);
        assert!((e.carrier() - 1_602.562_5e6).abs() < 1.0);
    }
}
