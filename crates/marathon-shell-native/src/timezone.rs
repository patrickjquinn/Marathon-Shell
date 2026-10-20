//! The time zone for a location fix: the `zone.tab` zone whose principal city
//! is nearest.

use std::path::Path;

use cxx_qt_lib::QString;

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "marathon::timezone"]
    extern "Rust" {
        /// "" without a zone table.
        fn nearest(latitude: f64, longitude: f64) -> QString;
    }
}

fn nearest(latitude: f64, longitude: f64) -> QString {
    QString::from(&nearest_in(Path::new("/usr/share/zoneinfo/zone.tab"), latitude, longitude).unwrap_or_default())
}

fn nearest_in(table: &Path, latitude: f64, longitude: f64) -> Option<String> {
    let (lat, lon) = (latitude.to_radians(), longitude.to_radians());
    let tab = std::fs::read_to_string(table).ok()?;
    tab.lines()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|line| {
            let mut fields = line.split('\t').skip(1);
            let (z_lat, z_lon) = coordinates(fields.next()?)?;
            let cos = lat.sin() * z_lat.sin() + lat.cos() * z_lat.cos() * (lon - z_lon).cos();
            Some((cos.clamp(-1.0, 1.0).acos(), fields.next()?))
        })
        .min_by(|a, b| a.0.total_cmp(&b.0))
        .map(|(_, zone)| zone.to_owned())
}

/// ISO 6709 `±DDMM[SS]±DDDMM[SS]`, in radians.
fn coordinates(field: &str) -> Option<(f64, f64)> {
    let split = field.get(1..)?.find(['+', '-'])? + 1;
    let (lat, lon) = field.split_at(split);
    Some((iso6709(lat, 2)?.to_radians(), iso6709(lon, 3)?.to_radians()))
}

fn iso6709(s: &str, degree_digits: usize) -> Option<f64> {
    let (sign, digits) = s.split_at_checked(1)?;
    if !(degree_digits + 2..=degree_digits + 4).contains(&digits.len()) || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let part = |range: std::ops::Range<usize>| digits.get(range).map_or(Some(0.0), |p| p.parse::<f64>().ok());
    let value = part(0..degree_digits)? + part(degree_digits..degree_digits + 2)? / 60.0 + part(degree_digits + 2..degree_digits + 4)? / 3600.0;
    Some(if sign == "-" { -value } else { value })
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn seconds_parse_and_the_date_line_wraps() {
        let dir = tempfile::tempdir().unwrap();
        let tab = dir.path().join("zone.tab");
        std::fs::write(
            &tab,
            "# comment\nUS\t+404251-0740023\tAmerica/New_York\tEastern\nFJ\t-1808+17825\tPacific/Fiji\nWS\t-1350-17144\tPacific/Apia\n",
        )
        .unwrap();
        assert_eq!(nearest_in(&tab, 40.7, -74.0).as_deref(), Some("America/New_York"));
        // 179.9 W is nearer Fiji (178.4 E) than Apia (171.7 W).
        assert_eq!(nearest_in(&tab, -18.0, -179.9).as_deref(), Some("Pacific/Fiji"));
        assert_eq!(nearest_in(&dir.path().join("none"), 0.0, 0.0), None);
    }

    #[test]
    fn the_system_table_knows_cities() {
        let tab = Path::new("/usr/share/zoneinfo/zone.tab");
        if !tab.exists() {
            return;
        }
        for (lat, lon, zone) in [(51.90, -8.47, "Europe/Dublin"), (51.51, -0.13, "Europe/London"), (40.68, -73.94, "America/New_York"), (-33.87, 151.21, "Australia/Sydney")] {
            assert_eq!(nearest_in(tab, lat, lon).as_deref(), Some(zone));
        }
    }
}
