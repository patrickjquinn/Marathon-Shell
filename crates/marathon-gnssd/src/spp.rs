//! Single-point positioning from L1 pseudoranges (the RTKLIB `pntpos`
//! approach without atmospheric models): Gauss-Newton on position and
//! receiver clock, with satellite clock and earth-rotation corrections.

use crate::lnav::Ephemeris;
use crate::orbit::{position, C, OMEGA_E};
use nalgebra::{Matrix4, Rotation3, Vector3, Vector4};

#[derive(Clone)]
pub struct Observation<'a> {
    pub eph: &'a Ephemeris,
    /// Pseudorange in metres.
    pub range: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Fix {
    pub ecef: Vector3<f64>,
    /// Receiver clock offset in seconds.
    pub clock: f64,
    /// Root-mean-square residual in metres.
    pub rms: f64,
}

/// Solves at GPS time of week `t` (receive time); needs four satellites.
#[allow(clippy::many_single_char_names, reason = "usual least-squares symbols")]
pub fn solve(obs: &[Observation], t: f64, start: Vector3<f64>) -> Option<Fix> {
    if obs.len() < 4 {
        return None;
    }
    let mut x = Vector4::new(start.x, start.y, start.z, 0.0);
    for _ in 0..10 {
        let mut n = Matrix4::zeros();
        let mut b = Vector4::zeros();
        let mut ss = 0.0;
        for o in obs {
            let tx = t - o.range / C;
            let (sat0, sat_clock) = position(o.eph, tx - position(o.eph, tx).1);
            let r0 = x.xyz();
            let travel = (sat0 - r0).norm() / C;
            let sat = Rotation3::from_axis_angle(&Vector3::z_axis(), -OMEGA_E * travel) * sat0;
            let los = sat - r0;
            let rho = los.norm();
            let h = Vector4::new(-los.x / rho, -los.y / rho, -los.z / rho, 1.0);
            let res = o.range - (rho + x.w - C * sat_clock);
            n += h * h.transpose();
            b += h * res;
            ss += res * res;
        }
        let dx = n.lu().solve(&b)?;
        x += dx;
        if dx.norm() < 1e-4 {
            #[allow(clippy::cast_precision_loss, reason = "a handful of satellites")]
            let rms = (ss / obs.len() as f64).sqrt();
            return Some(Fix {
                ecef: x.xyz(),
                clock: x.w / C,
                rms,
            });
        }
    }
    None
}

/// WGS-84 latitude, longitude (degrees) and ellipsoidal height (m).
pub fn geodetic(p: &Vector3<f64>) -> (f64, f64, f64) {
    const A: f64 = 6_378_137.0;
    const E2: f64 = 6.694_379_990_14e-3;
    let rxy = p.x.hypot(p.y);
    let mut lat = p.z.atan2(rxy * (1.0 - E2));
    let mut h = 0.0;
    for _ in 0..10 {
        let n = A / (1.0 - E2 * lat.sin().powi(2)).sqrt();
        h = rxy / lat.cos() - n;
        lat = p.z.atan2(rxy * (1.0 - E2 * n / (n + h)));
    }
    (lat.to_degrees(), p.y.atan2(p.x).to_degrees(), h)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    /// A GPS-like constellation of circular orbits (six planes of four); ranges are made
    /// with the same model the solver inverts, so the fix must come back.
    #[test]
    fn recovers_position_and_clock() {
        let truth = Vector3::new(3_791_000.0, -110_000.0, 5_110_000.0);
        let clock = 1.2e-4;
        let t = 200_000.0;
        let ephs: Vec<Ephemeris> = (0..24)
            .map(|k| Ephemeris {
                sqrt_a: 26_560_000f64.sqrt(),
                toe: t,
                i0: 0.96,
                omega0: f64::from(k % 6) * 1.047,
                m0: f64::from(k / 6) * 1.571 + f64::from(k % 6) * 0.26,
                af0: f64::from(k) * 1e-5,
                ..Ephemeris::default()
            })
            .filter(|e| {
                let (s, _) = position(e, t);
                // above about 10 degrees elevation
                (s - truth).normalize().dot(&truth.normalize()) > 0.17
            })
            .collect();
        assert!(ephs.len() >= 4);
        let obs: Vec<Observation> = ephs
            .iter()
            .map(|e| {
                // Fixed point of the solver's own geometry.
                let mut range = 2.2e7;
                for _ in 0..5 {
                    let tx = t - range / C;
                    let (s0, sc) = position(e, tx - position(e, tx).1);
                    let tr = (s0 - truth).norm() / C;
                    let s = Rotation3::from_axis_angle(&Vector3::z_axis(), -OMEGA_E * tr) * s0;
                    range = (s - truth).norm() + C * clock - C * sc;
                }
                Observation { eph: e, range }
            })
            .collect();
        let fix = solve(&obs, t, Vector3::zeros()).unwrap();
        assert!((fix.ecef - truth).norm() < 0.01, "{fix:?}");
        assert!((fix.clock - clock).abs() < 1e-10);
        let (lat, lon, _) = geodetic(&fix.ecef);
        // Bowring's closed form gives 53.601548514, -1.662033202.
        assert!(
            (lat - 53.601_548_514).abs() < 1e-8 && (lon + 1.662_033_202).abs() < 1e-8,
            "{lat} {lon}"
        );
    }
}
