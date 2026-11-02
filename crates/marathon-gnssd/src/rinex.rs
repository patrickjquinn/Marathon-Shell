//! GPS, BeiDou and GLONASS records of a RINEX 3 navigation file (broadcast
//! ephemeris), the network aiding source until the DSP's navigation bits are
//! decoded.

use crate::glonass;
use crate::lnav::Ephemeris;
use nalgebra::Vector3;
use std::collections::HashMap;

/// GPS minus UTC, valid since 2017.
pub const LEAP_SECONDS: f64 = 18.0;

#[derive(Default)]
pub struct Nav {
    pub gps: HashMap<u8, Vec<Ephemeris>>,
    /// Times in BDT.
    pub beidou: HashMap<u8, Vec<Ephemeris>>,
    pub glonass: HashMap<u8, Vec<glonass::Ephemeris>>,
}

fn num(s: &str) -> Option<f64> {
    s.trim().replace(['D', 'd'], "E").parse().ok()
}

/// Seconds of the GPS week of a date and time in the GPS time scale.
pub fn seconds_of_week(at: chrono::NaiveDateTime) -> Option<f64> {
    let gps_epoch = chrono::NaiveDate::from_ymd_opt(1980, 1, 6)?.and_hms_opt(0, 0, 0)?;
    #[allow(clippy::cast_precision_loss, reason = "seconds within a week")]
    Some((at - gps_epoch).num_seconds().rem_euclid(604_800) as f64)
}

/// Every GPS, BeiDou and GLONASS ephemeris in `text`, by satellite number.
pub fn parse(text: &str) -> Nav {
    let mut nav = Nav::default();
    let mut lines = text
        .lines()
        .skip_while(|l| !l.contains("END OF HEADER"))
        .skip(1);
    while let Some(l) = lines.next() {
        let n = match l.chars().next() {
            Some('R' | 'S') => 3,
            Some(_) => 7,
            None => continue,
        };
        let body: Vec<&str> = (0..n).filter_map(|_| lines.next()).collect();
        let Ok(sv) = l.get(1..3).unwrap_or("").trim().parse::<u8>() else {
            continue;
        };
        match l.as_bytes()[0] {
            b'G' => {
                if let Some(e) = kepler_record(l, &body) {
                    nav.gps.entry(sv).or_default().push(e);
                }
            }
            b'C' => {
                if let Some(e) = kepler_record(l, &body) {
                    nav.beidou.entry(sv).or_default().push(e);
                }
            }
            b'R' => {
                if let Some(e) = glonass_record(l, &body) {
                    nav.glonass.entry(sv).or_default().push(e);
                }
            }
            _ => {}
        }
    }
    nav
}

fn values(head: &str, body: &[&str]) -> Option<Vec<f64>> {
    let mut v = vec![
        num(head.get(23..42)?)?,
        num(head.get(42..61)?)?,
        num(head.get(61..80)?)?,
    ];
    // Blank (spare) fields still take their place.
    for l in body {
        for k in 0..4 {
            v.push(
                l.get(4 + 19 * k..(23 + 19 * k).min(l.len()))
                    .and_then(num)
                    .unwrap_or(0.0),
            );
        }
    }
    Some(v)
}

fn glonass_record(head: &str, body: &[&str]) -> Option<glonass::Ephemeris> {
    let utc = chrono::NaiveDateTime::parse_from_str(head.get(4..23)?, "%Y %m %d %H %M %S").ok()?;
    let v = values(head, body)?;
    if v.len() < 15 || body.len() != 3 {
        return None;
    }
    let km = |i: usize, j: usize, k: usize| Vector3::new(v[i], v[j], v[k]) * 1e3;
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "RINEX integer fields"
    )]
    Some(glonass::Ephemeris {
        tb: (seconds_of_week(utc)? + LEAP_SECONDS) % 604_800.0,
        clock: v[0],
        gamma: v[1],
        pos: km(3, 7, 11),
        vel: km(4, 8, 12),
        acc: km(5, 9, 13),
        health: v[6] as u8,
        k: v[10] as i8,
    })
}

fn kepler_record(head: &str, body: &[&str]) -> Option<Ephemeris> {
    let toc = chrono::NaiveDateTime::parse_from_str(head.get(4..23)?, "%Y %m %d %H %M %S").ok()?;
    let v = values(head, body)?;
    if v.len() < 27 {
        return None;
    }
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "RINEX integer fields"
    )]
    Some(Ephemeris {
        toc: seconds_of_week(toc)?,
        af0: v[0],
        af1: v[1],
        af2: v[2],
        iode: v[3] as u8,
        crs: v[4],
        dn: v[5],
        m0: v[6],
        cuc: v[7],
        e: v[8],
        cus: v[9],
        sqrt_a: v[10],
        toe: v[11],
        cic: v[12],
        omega0: v[13],
        cis: v[14],
        i0: v[15],
        crc: v[16],
        omega: v[17],
        omega_dot: v[18],
        idot: v[19],
        week: v[21] as u16,
        health: v[24] as u8,
        tgd: v[25],
        iodc: v.get(26).map_or(0, |x| *x as u16),
    })
}

/// The ephemeris closest to `t` (seconds of week).
pub fn nearest(list: &[Ephemeris], t: f64) -> Option<&Ephemeris> {
    list.iter().min_by(|a, b| {
        crate::orbit::dt(t, a.toe)
            .abs()
            .total_cmp(&crate::orbit::dt(t, b.toe).abs())
    })
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn week_seconds() {
        // 2026-11-02 (Monday) 10:18:30 is 1 day 10:18:30 into GPS week 2443.
        let at = |s| chrono::NaiveDateTime::parse_from_str(s, "%Y %m %d %H %M %S").unwrap();
        assert_eq!(seconds_of_week(at("2026 11 02 10 18 30")), Some(123_510.0));
        assert_eq!(seconds_of_week(at("1980 01 06 00 00 00")), Some(0.0));
    }

    #[test]
    fn gps_record_from_text() {
        // A synthetic record in RINEX 3 layout.
        let text =
            "     3.04           N: GNSS NAV DATA    M: MIXED            RINEX VERSION / TYPE\n\
                                                                END OF HEADER\n\
G30 2026 11 02 10 00 00 1.000000000000E-04 2.000000000000E-12 0.000000000000E+00\n     \
3.700000000000E+01 1.000000000000E+01 4.000000000000E-09 1.000000000000E+00\n     \
1.000000000000E-06 5.000000000000E-03 2.000000000000E-06 5.153700000000E+03\n     \
1.224000000000E+05 1.000000000000E-08 2.000000000000E+00 2.000000000000E-08\n     \
9.600000000000E-01 2.000000000000E+02 3.000000000000E-01-8.000000000000E-09\n     \
1.000000000000E-10 1.000000000000E+00 2.443000000000E+03 0.000000000000E+00\n     \
2.000000000000E+00 0.000000000000E+00-1.000000000000E-08 3.700000000000E+01\n     \
1.188000000000E+05 4.000000000000E+00\n";
        let e = parse(text).gps[&30][0];
        assert_eq!((e.week, e.iode, e.iodc), (2443, 37, 37));
        assert!((e.toe - 122_400.0).abs() < 1e-9 && (e.toc - 122_400.0).abs() < 1e-9);
        assert!((e.sqrt_a - 5153.7).abs() < 1e-9 && (e.omega_dot + 8e-9).abs() < 1e-20);
        assert!((e.tgd + 1e-8).abs() < 1e-20);
    }

    #[test]
    fn beidou_record_keeps_blank_fields_in_place() {
        // BeiDou records leave spare fields blank; TGD1 must not shift.
        let text =
            "     3.05           N: GNSS NAV DATA    M: MIXED            RINEX VERSION / TYPE\n\
                                                                END OF HEADER\n\
C36 2026 11 02 09 00 00 2.135041868314e-04-5.955236304089e-12 0.000000000000e+00\n     \
1.000000000000e+00 2.232812500000e+01 4.035882396416e-09 1.328131143342e+00\n     \
1.090578734875e-06 5.441338289529e-04 1.008482649922e-05 5.282651386261e+03\n     \
1.188000000000e+05-1.629814505577e-08 2.396965464078e+00 1.257285475731e-07\n     \
9.454162771142e-01 1.494687500000e+02-5.507733254626e-01-6.808855044714e-09\n     \
3.157274370293e-10                    1.087000000000e+03                   \n     \
2.000000000000e+00 0.000000000000e+00-2.070000000000e-08-2.070000000000e-08\n     \
1.188000000000e+05 1.000000000000e+00\n";
        let e = parse(text).beidou[&36][0];
        assert_eq!(e.week, 1087);
        assert!((e.tgd + 2.07e-8).abs() < 1e-20 && (e.toc - 118_800.0).abs() < 1e-9);
    }
}
