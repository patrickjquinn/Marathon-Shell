//! Where the phone is, roughly, without asking for the location: the
//! coordinates tzdata gives the time zone's principal city.

use std::path::Path;

/// `+5320-00615` (or with seconds, `+515230-0000713`) as degrees.
fn coordinates(iso: &str) -> Option<(f64, f64)> {
    let split = iso[1..].find(['+', '-'])? + 1;
    let (lat, lon) = iso.split_at(split);
    Some((degrees(lat, 2)?, degrees(lon, 3)?))
}

fn degrees(text: &str, whole: usize) -> Option<f64> {
    let sign = match text.as_bytes().first()? {
        b'+' => 1.0,
        b'-' => -1.0,
        _ => return None,
    };
    let digits = &text[1..];
    let part = |from: usize, len: usize| -> Option<f64> {
        digits
            .get(from..from + len)
            .map_or(Some(0.0), |d| d.parse().ok())
    };
    let d = part(0, whole)?;
    let m = part(whole, 2)?;
    let s = part(whole + 2, 2)?;
    Some(sign * (d + m / 60.0 + s / 3600.0))
}

pub struct Home {
    pub lat: f64,
    pub lon: f64,
    /// The zone's (first) country, ISO 3166 alpha-2.
    pub country: String,
}

/// The zone's coordinates and country in a `zone1970.tab`.
pub fn zone_home(table: &str, zone: &str) -> Option<Home> {
    table.lines().filter(|l| !l.starts_with('#')).find_map(|l| {
        let mut f = l.split('\t');
        let (codes, iso, name) = (f.next()?, f.next()?, f.next()?);
        if name != zone {
            return None;
        }
        let (lat, lon) = coordinates(iso)?;
        let country = codes.split(',').next().unwrap_or_default().to_owned();
        Some(Home { lat, lon, country })
    })
}

/// The time zone's city, from /etc/localtime; None when it names none.
pub fn home() -> Option<Home> {
    let link = std::fs::read_link("/etc/localtime").ok()?;
    let link = link.to_string_lossy();
    let zone = link.split("zoneinfo/").nth(1)?;
    let table = std::fs::read_to_string(Path::new("/usr/share/zoneinfo/zone1970.tab")).ok()?;
    zone_home(&table, zone)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_zone_gives_its_city() {
        let table = "# comment\nIE\t+5320-00615\tEurope/Dublin\n\
                     GB,GG,IM,JE\t+513030-0000731\tEurope/London\n";
        let dublin = zone_home(table, "Europe/Dublin").map(|h| (h.lat, h.lon, h.country));
        let (lat, lon, cc) = dublin.unwrap_or_default();
        assert!((lat - 53.333).abs() < 0.01 && (lon + 6.25).abs() < 0.01 && cc == "IE");
        let london = zone_home(table, "Europe/London").map(|h| (h.lat, h.lon, h.country));
        let (lat, lon, cc) = london.unwrap_or_default();
        assert!((lat - 51.508).abs() < 0.01 && (lon + 0.125).abs() < 0.01 && cc == "GB");
        assert!(zone_home(table, "Mars/Olympus").is_none());
    }
}
