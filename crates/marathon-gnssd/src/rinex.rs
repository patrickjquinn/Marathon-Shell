//! GPS records of a RINEX 3 navigation file (broadcast ephemeris), the
//! network aiding source until the DSP's navigation bits are decoded.

use crate::lnav::Ephemeris;
use std::collections::HashMap;

fn num(s: &str) -> Option<f64> {
    s.trim().replace(['D', 'd'], "E").parse().ok()
}

/// Seconds of the GPS week of a date and time in the GPS time scale.
pub fn seconds_of_week(at: chrono::NaiveDateTime) -> Option<f64> {
    let gps_epoch = chrono::NaiveDate::from_ymd_opt(1980, 1, 6)?.and_hms_opt(0, 0, 0)?;
    #[allow(clippy::cast_precision_loss, reason = "seconds within a week")]
    Some((at - gps_epoch).num_seconds().rem_euclid(604_800) as f64)
}

/// Every GPS ephemeris in `text`, by PRN.
pub fn parse_gps(text: &str) -> HashMap<u8, Vec<Ephemeris>> {
    let mut out: HashMap<u8, Vec<Ephemeris>> = HashMap::new();
    let mut lines = text
        .lines()
        .skip_while(|l| !l.contains("END OF HEADER"))
        .skip(1)
        .peekable();
    while let Some(l) = lines.next() {
        let n = match l.chars().next() {
            Some('R' | 'S') => 3,
            Some(_) => 7,
            None => continue,
        };
        let body: Vec<&str> = (0..n).filter_map(|_| lines.next()).collect();
        if !l.starts_with('G') || body.len() != 7 {
            continue;
        }
        let Some(e) = gps_record(l, &body) else {
            continue;
        };
        if let Ok(prn) = l[1..3].trim().parse() {
            out.entry(prn).or_default().push(e);
        }
    }
    out
}

fn gps_record(head: &str, body: &[&str]) -> Option<Ephemeris> {
    let toc = chrono::NaiveDateTime::parse_from_str(head.get(4..23)?, "%Y %m %d %H %M %S").ok()?;
    let mut v = vec![
        num(head.get(23..42)?)?,
        num(head.get(42..61)?)?,
        num(head.get(61..80)?)?,
    ];
    for l in body {
        for k in 0..4 {
            if let Some(x) = l.get(4 + 19 * k..23 + 19 * k).and_then(num) {
                v.push(x);
            }
        }
    }
    if v.len() < 26 {
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
        let g = parse_gps(text);
        let e = g[&30][0];
        assert_eq!((e.week, e.iode, e.iodc), (2443, 37, 37));
        assert!((e.toe - 122_400.0).abs() < 1e-9 && (e.toc - 122_400.0).abs() < 1e-9);
        assert!((e.sqrt_a - 5153.7).abs() < 1e-9 && (e.omega_dot + 8e-9).abs() < 1e-20);
        assert!((e.tgd + 1e-8).abs() < 1e-20);
    }
}
