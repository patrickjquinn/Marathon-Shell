//! Single-point positioning from code pseudoranges (the RTKLIB `pntpos`
//! approach): weighted Gauss-Newton on position and one receiver clock bias
//! per satellite system, with satellite clock and earth-rotation corrections
//! and an optional soft height constraint.

use crate::orbit::{C, OMEGA_E};
use crate::sat::Sat;
use nalgebra::{DMatrix, DVector, Matrix3, Rotation3, Vector3};

#[derive(Debug, Clone, Copy)]
pub struct Observation<'a> {
    pub sat: Sat<'a>,
    /// Pseudorange in metres.
    pub range: f64,
    /// Its standard deviation in metres.
    pub sigma: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Fix {
    pub ecef: Vector3<f64>,
    /// Receiver clock offset of the first system used, seconds.
    pub clock: f64,
    /// Root-mean-square of the residuals divided by their sigmas.
    pub chi: f64,
    pub hdop: f64,
    /// Measurements beyond the unknowns.
    pub redundancy: usize,
}

const SYSTEMS: usize = 3;

/// Solves at GPS time of week `t` (receive time). `height` is an ellipsoidal
/// height and its sigma, used as one more measurement; `bias_sigma[s]`, when
/// set, ties system `s`'s clock to the first system's within that sigma.
#[allow(clippy::many_single_char_names, reason = "usual least-squares symbols")]
pub fn solve(
    obs: &[Observation],
    t: f64,
    start: Vector3<f64>,
    height: Option<(f64, f64)>,
    bias_sigma: [Option<f64>; SYSTEMS],
) -> Option<Fix> {
    let mut used = [false; SYSTEMS];
    for o in obs {
        used[o.sat.system()] = true;
    }
    let column: Vec<Option<usize>> = (0..SYSTEMS)
        .scan(3, |next, s| {
            Some(used[s].then(|| {
                *next += 1;
                *next - 1
            }))
        })
        .collect();
    let unknowns = 3 + used.iter().filter(|&&u| u).count();
    let first = column.iter().flatten().copied().next()?;
    // Clock-bias priors for the systems after the first one used.
    let priors: Vec<(usize, f64)> = (0..SYSTEMS)
        .filter_map(|s| Some((column[s].filter(|&c| c != first)?, bias_sigma[s]?)))
        .collect();
    let rows = obs.len() + usize::from(height.is_some()) + priors.len();
    if rows < unknowns {
        return None;
    }
    let mut x = DVector::<f64>::zeros(unknowns);
    x.fixed_rows_mut::<3>(0).copy_from(&start);
    for iteration in 0..15 {
        let mut h = DMatrix::<f64>::zeros(rows, unknowns);
        let mut r = DVector::<f64>::zeros(rows);
        let mut w = DVector::<f64>::zeros(rows);
        let pos: Vector3<f64> = x.fixed_rows::<3>(0).into();
        for (i, o) in obs.iter().enumerate() {
            let col = column[o.sat.system()]?;
            let tx = t - o.range / C;
            let (sat0, clock) = o.sat.position(tx - o.sat.position(tx).1);
            let travel = (sat0 - pos).norm() / C;
            let sat = Rotation3::from_axis_angle(&Vector3::z_axis(), -OMEGA_E * travel) * sat0;
            let los = sat - pos;
            let rho = los.norm();
            h.row_mut(i)
                .columns_mut(0, 3)
                .copy_from(&(-los / rho).transpose());
            h[(i, col)] = 1.0;
            r[i] = o.range - (rho + x[col] - C * clock);
            w[i] = 1.0 / (o.sigma * o.sigma);
        }
        if let Some((h0, sigma)) = height {
            let i = obs.len();
            let (lat, lon, hh) = geodetic(&pos);
            let up = up_vector(lat, lon);
            h.row_mut(i).columns_mut(0, 3).copy_from(&up.transpose());
            r[i] = h0 - hh;
            w[i] = 1.0 / (sigma * sigma);
        }
        for (j, &(col, sigma)) in priors.iter().enumerate() {
            let i = rows - priors.len() + j;
            h[(i, col)] = 1.0;
            h[(i, first)] = -1.0;
            r[i] = x[first] - x[col];
            w[i] = 1.0 / (sigma * sigma);
        }
        let hw = h.transpose() * DMatrix::from_diagonal(&w);
        let dx = (&hw * &h).lu().solve(&(&hw * &r))?;
        x += &dx;
        // Converged; centimetre noise in the satellite model can stop it
        // short of that, so the last iterations settle for decimetres.
        if dx.norm() < if iteration < 10 { 1e-2 } else { 0.3 } {
            let pos: Vector3<f64> = x.fixed_rows::<3>(0).into();
            let res = &r - &h * &dx;
            #[allow(clippy::cast_precision_loss, reason = "a handful of rows")]
            let chi = (res
                .iter()
                .zip(w.iter())
                .map(|(e, w)| e * e * w)
                .sum::<f64>()
                / rows as f64)
                .sqrt();
            return Some(Fix {
                ecef: pos,
                clock: x[first] / C,
                chi,
                hdop: hdop(&h, &pos)?,
                redundancy: rows - unknowns,
            });
        }
    }
    None
}

fn up_vector(lat: f64, lon: f64) -> Vector3<f64> {
    let (la, lo) = (lat.to_radians(), lon.to_radians());
    Vector3::new(la.cos() * lo.cos(), la.cos() * lo.sin(), la.sin())
}

/// Horizontal dilution of precision of the unweighted geometry.
fn hdop(h: &DMatrix<f64>, pos: &Vector3<f64>) -> Option<f64> {
    let q = (h.transpose() * h).try_inverse()?;
    let qp: Matrix3<f64> = q.fixed_view::<3, 3>(0, 0).into();
    let (lat, lon, _) = geodetic(pos);
    let (la, lo) = (lat.to_radians(), lon.to_radians());
    let east = Vector3::new(-lo.sin(), lo.cos(), 0.0);
    let north = Vector3::new(-la.sin() * lo.cos(), -la.sin() * lo.sin(), la.cos());
    Some((east.dot(&(qp * east)) + north.dot(&(qp * north))).sqrt())
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
    use crate::lnav::Ephemeris;
    use crate::orbit::position;

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
                Observation {
                    sat: Sat::Gps(e),
                    range,
                    sigma: 5.0,
                }
            })
            .collect();
        let fix = solve(&obs, t, Vector3::zeros(), None, [None; 3]).unwrap();
        assert!((fix.ecef - truth).norm() < 0.01, "{fix:?}");
        assert!((fix.clock - clock).abs() < 1e-10 && fix.hdop > 0.5 && fix.hdop < 5.0);
        let (_, _, h) = geodetic(&truth);
        // Three satellites and the height: still the position.
        let three = solve(
            &obs[..3],
            t,
            truth + Vector3::new(300.0, -200.0, 100.0),
            Some((h, 1.0)),
            [None; 3],
        )
        .unwrap();
        assert!(
            (three.ecef - truth).norm() < 0.05 && three.redundancy == 0,
            "{three:?}"
        );
        let (lat, lon, _) = geodetic(&fix.ecef);
        // Bowring's closed form gives 53.601548514, -1.662033202.
        assert!(
            (lat - 53.601_548_514).abs() < 1e-8 && (lon + 1.662_033_202).abs() < 1e-8,
            "{lat} {lon}"
        );
    }
}
