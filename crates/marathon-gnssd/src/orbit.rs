//! Satellite position and clock from a GPS broadcast ephemeris
//! (IS-GPS-200 tables 20-IV and 20.3.3.3.3.1).

use crate::lnav::Ephemeris;
use nalgebra::{Rotation3, Vector3};

pub const MU: f64 = 3.986_005e14;
pub const OMEGA_E: f64 = 7.292_115_146_7e-5;
pub const C: f64 = 299_792_458.0;
const F: f64 = -4.442_807_633e-10;
const HALF_WEEK: f64 = 302_400.0;

/// Time difference within a GPS week, wrapped to +-half a week.
pub fn dt(t: f64, t0: f64) -> f64 {
    let d = t - t0;
    if d > HALF_WEEK {
        d - 2.0 * HALF_WEEK
    } else if d < -HALF_WEEK {
        d + 2.0 * HALF_WEEK
    } else {
        d
    }
}

/// Which Keplerian broadcast model an ephemeris follows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Model {
    Gps,
    /// BeiDou (CGCS2000 constants); `geo` for the geostationary satellites.
    Beidou {
        geo: bool,
    },
}

/// ECEF position (m) and clock offset (s, including relativity and TGD for
/// L1) at GPS time of week `t` (transmit time).
pub fn position(e: &Ephemeris, t: f64) -> (Vector3<f64>, f64) {
    kepler(e, t, Model::Gps)
}

/// ECEF position and clock offset from a Keplerian ephemeris at time `t` in
/// the ephemeris' own time scale (GPS time, or BDT for BeiDou).
#[allow(
    clippy::many_single_char_names,
    reason = "IS-GPS-200 / BDS ICD symbols"
)]
pub fn kepler(e: &Ephemeris, t: f64, model: Model) -> (Vector3<f64>, f64) {
    let (mu, we) = match model {
        Model::Gps => (MU, OMEGA_E),
        Model::Beidou { .. } => (3.986_004_418e14, 7.292_115e-5),
    };
    let a = e.sqrt_a * e.sqrt_a;
    let tk = dt(t, e.toe);
    let m = e.m0 + ((mu / (a * a * a)).sqrt() + e.dn) * tk;
    let mut ek = m;
    for _ in 0..30 {
        let next = m + e.e * ek.sin();
        if (next - ek).abs() < 1e-14 {
            ek = next;
            break;
        }
        ek = next;
    }
    let v = ((1.0 - e.e * e.e).sqrt() * ek.sin()).atan2(ek.cos() - e.e);
    let phi = v + e.omega;
    let (s2, c2) = (2.0 * phi).sin_cos();
    let u = phi + e.cus * s2 + e.cuc * c2;
    let r = a * (1.0 - e.e * ek.cos()) + e.crs * s2 + e.crc * c2;
    let i = e.i0 + e.cis * s2 + e.cic * c2 + e.idot * tk;
    let (xp, yp) = (r * u.cos(), r * u.sin());
    let geo = model == Model::Beidou { geo: true };
    let om = if geo {
        e.omega0 + e.omega_dot * tk - we * e.toe
    } else {
        e.omega0 + (e.omega_dot - we) * tk - we * e.toe
    };
    let mut pos = Vector3::new(
        xp * om.cos() - yp * i.cos() * om.sin(),
        xp * om.sin() + yp * i.cos() * om.cos(),
        yp * i.sin(),
    );
    if geo {
        // BDS ICD: Rz(we tk) Rx(-5 deg), passive rotations.
        let tilt = Rotation3::from_axis_angle(&Vector3::x_axis(), 5f64.to_radians());
        pos = Rotation3::from_axis_angle(&Vector3::z_axis(), -we * tk) * (tilt * pos);
    }
    let tc = dt(t, e.toc);
    let clock = e.af0 + e.af1 * tc + e.af2 * tc * tc + F * e.e * e.sqrt_a * ek.sin() - e.tgd;
    (pos, clock)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn circular() -> Ephemeris {
        Ephemeris {
            sqrt_a: 26_560_000f64.sqrt(),
            toe: 0.0,
            i0: 0.96,
            ..Ephemeris::default()
        }
    }

    #[test]
    fn circular_orbit_radius_and_period() {
        let e = circular();
        let (p0, clk) = position(&e, 0.0);
        assert!((p0.norm() - 26_560_000.0).abs() < 1e-3);
        assert!(clk.abs() < 1e-15);
        // One orbital period later the inertial position repeats; in ECEF it
        // has turned with the earth by OMEGA_E * T.
        let a: f64 = 26_560_000.0;
        let period = 2.0 * std::f64::consts::PI * (a * a * a / MU).sqrt();
        let (p1, _) = position(&e, period);
        let back = nalgebra::Rotation3::from_axis_angle(&Vector3::z_axis(), OMEGA_E * period) * p1;
        assert!((back - p0).norm() < 1e-3);
    }

    #[test]
    fn week_wrap() {
        assert!((dt(10.0, 604_790.0) - 20.0).abs() < 1e-9);
        assert!((dt(604_790.0, 10.0) + 20.0).abs() < 1e-9);
    }
}
