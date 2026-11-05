//! GPS almanac (IS-GPS-200, 20.3.3.5.1.2): coarse orbits of the whole
//! constellation from subframes 4 and 5, good for weeks. A cold start uses
//! them to search the satellites that are up.

use crate::lnav::{bits, header, sbits, Ephemeris};
use crate::orbit::{MU, OMEGA_E};
use std::f64::consts::PI;

const WEEK: f64 = 604_800.0;

/// One satellite's almanac; `toa` is absolute GPS time (seconds since the
/// GPS epoch), resolved against the clock when it was received.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Almanac {
    pub prn: u8,
    pub health: u8,
    pub toa: f64,
    pub e: f64,
    pub i0: f64,
    pub omega_dot: f64,
    pub sqrt_a: f64,
    pub omega0: f64,
    pub omega: f64,
    pub m0: f64,
    pub af0: f64,
    pub af1: f64,
}

#[allow(clippy::cast_precision_loss, reason = "fields are at most 24 bits")]
fn f(v: i64, exp: i32) -> f64 {
    v as f64 * 2f64.powi(exp)
}

/// The almanac page in a subframe 4 or 5, if it is one, received at GPS
/// time `now` (absolute seconds).
#[allow(clippy::cast_possible_truncation, reason = "field widths fit")]
pub fn decode(b: &[u8; 30], now: f64) -> Option<Almanac> {
    let (id, _) = header(b);
    let prn = bits(b, 50, 6) as u8;
    if !matches!(id, 4 | 5) || bits(b, 48, 2) != 1 || !(1..=32).contains(&prn) {
        return None;
    }
    let u = |p, l| bits(b, p, l).cast_signed();
    let sow = f(u(72, 8), 12);
    let toa = now + crate::orbit::dt(sow, now.rem_euclid(WEEK));
    let sqrt_a = f(u(120, 24), -11);
    // Empty pages carry zeros.
    if sqrt_a < 4_000.0 {
        return None;
    }
    Some(Almanac {
        prn,
        health: bits(b, 112, 8) as u8,
        toa,
        e: f(u(56, 16), -21),
        i0: (0.30 + f(sbits(b, 80, 16), -19)) * PI,
        omega_dot: f(sbits(b, 96, 16), -38) * PI,
        sqrt_a,
        omega0: f(sbits(b, 144, 24), -23) * PI,
        omega: f(sbits(b, 168, 24), -23) * PI,
        m0: f(sbits(b, 192, 24), -23) * PI,
        af0: f(sbits(b, 216, 8) << 3 | u(235, 3), -20),
        af1: f(sbits(b, 224, 11), -38),
    })
}

impl Almanac {
    /// An ephemeris for GPS time `now` (absolute seconds), with the whole
    /// weeks since the almanac's reference time folded into the angles so
    /// that the usual half-week time wrap does not lose them.
    pub fn ephemeris(&self, now: f64) -> Ephemeris {
        let weeks = ((now - self.toa) / WEEK).round() * WEEK;
        let a = self.sqrt_a * self.sqrt_a;
        let n = (MU / (a * a * a)).sqrt();
        let toe = self.toa.rem_euclid(WEEK);
        Ephemeris {
            health: self.health,
            e: self.e,
            i0: self.i0,
            omega_dot: self.omega_dot,
            sqrt_a: self.sqrt_a,
            omega0: self.omega0 + (self.omega_dot - OMEGA_E) * weeks,
            omega: self.omega,
            m0: self.m0 + n * weeks,
            af0: self.af0 + self.af1 * weeks,
            af1: self.af1,
            toe,
            toc: toe,
            ..Ephemeris::default()
        }
    }

    /// The almanac as one line of numbers, for the state directory.
    pub fn to_line(&self) -> String {
        let v = [
            self.toa,
            self.e,
            self.i0,
            self.omega_dot,
            self.sqrt_a,
            self.omega0,
            self.omega,
            self.m0,
            self.af0,
            self.af1,
        ];
        std::iter::once(format!("{} {}", self.prn, self.health))
            .chain(v.iter().map(|x| format!("{x:e}")))
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Reads back [`Almanac::to_line`].
    pub fn from_line(s: &str) -> Option<Self> {
        let w: Vec<&str> = s.split_whitespace().collect();
        let v: Vec<f64> = w
            .get(2..)?
            .iter()
            .map(|x| x.parse().ok())
            .collect::<Option<_>>()?;
        let [toa, e, i0, omega_dot, sqrt_a, omega0, omega, m0, af0, af1] = v[..] else {
            return None;
        };
        Some(Self {
            prn: w[0].parse().ok()?,
            health: w[1].parse().ok()?,
            toa,
            e,
            i0,
            omega_dot,
            sqrt_a,
            omega0,
            omega,
            m0,
            af0,
            af1,
        })
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use crate::lnav::tests::{put, subframe};
    use crate::orbit::{kepler, Model};

    #[test]
    fn page_round_trip_and_weeks_later() {
        let now = 2_390.0 * WEEK + 123_000.0;
        let sf = subframe(5, |b| {
            put(b, 48, 2, 1);
            put(b, 50, 6, 7);
            put(b, 56, 16, 0x2000);
            put(b, 72, 8, 30); // toa 122880 s
            put(b, 80, 16, 0x1000);
            put(b, 120, 24, 0xa1_0000); // sqrt(A) ~ 5152 m^0.5
            put(b, 192, 24, 0x10_0000);
        });
        let a = decode(&sf, now).unwrap();
        assert_eq!(a.prn, 7);
        assert!((a.toa - (2_390.0 * WEEK + 122_880.0)).abs() < 1e-6);
        assert_eq!(Almanac::from_line(&a.to_line()), Some(a));
        // Whole weeks later the folded ephemeris equals propagating the orbit
        // continuously: compare with three days, where no folding happens.
        let t = a.toa + 3.0 * 86_400.0;
        let direct = kepler(&a.ephemeris(t), t.rem_euclid(WEEK), Model::Gps).0;
        let later = t + 2.0 * WEEK;
        let folded = kepler(&a.ephemeris(later), later.rem_euclid(WEEK), Model::Gps).0;
        let mut b = a;
        b.toa = a.toa + 2.0 * WEEK;
        let a2 = a.sqrt_a.powi(2);
        b.m0 = a.m0 + (MU / (a2 * a2 * a2)).sqrt() * 2.0 * WEEK;
        b.omega0 = a.omega0 + (a.omega_dot - OMEGA_E) * 2.0 * WEEK;
        let shifted = kepler(&b.ephemeris(later), later.rem_euclid(WEEK), Model::Gps).0;
        assert!((folded - shifted).norm() < 1.0, "{folded} {shifted}");
        assert!(direct.norm() > 2.0e7);
    }
}
