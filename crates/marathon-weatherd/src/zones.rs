//! The time zone for a pinned location. Nominatim doesn't return one, so
//! take the zone of the country's nearest principal city in tzdata's
//! zone1970.tab. Without a country (or tzdata) the caller uses the system
//! zone.

use tz::TimeZone;

const ZONE_TAB: &str = "/usr/share/zoneinfo/zone1970.tab";

/// `+6010+02458` or `+404251-0740023` (±DDMM[SS]±DDDMM[SS]) as degrees.
fn parse_iso6709(s: &str) -> Option<(f64, f64)> {
    let split = s[1..].find(['+', '-'])? + 1;
    let part = |p: &str, deg_digits: usize| -> Option<f64> {
        let sign = if p.starts_with('-') { -1.0 } else { 1.0 };
        let digits = &p[1..];
        let num = |r: std::ops::Range<usize>| digits.get(r)?.parse::<f64>().ok();
        let deg = num(0..deg_digits)?;
        let min = num(deg_digits..deg_digits + 2)?;
        let sec = num(deg_digits + 2..deg_digits + 4).unwrap_or(0.0);
        Some(sign * (deg + min / 60.0 + sec / 3600.0))
    };
    Some((part(&s[..split], 2)?, part(&s[split..], 3)?))
}

/// The zone in `country` (ISO 3166 alpha-2) whose principal city is nearest.
pub fn nearest_zone(table: &str, country: &str, latitude: f64, longitude: f64) -> Option<String> {
    let country = country.to_ascii_uppercase();
    table
        .lines()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|line| {
            let mut cols = line.split('\t');
            let codes = cols.next()?;
            let (lat, lon) = parse_iso6709(cols.next()?)?;
            let zone = cols.next()?;
            codes.split(',').any(|c| c == country).then(|| {
                let dlon = (lon - longitude) * latitude.to_radians().cos();
                ((lat - latitude).powi(2) + dlon.powi(2), zone)
            })
        })
        .min_by(|a, b| a.0.total_cmp(&b.0))
        .map(|(_, zone)| zone.to_owned())
}

pub fn zone_for(country: &str, latitude: f64, longitude: f64) -> Option<String> {
    let table = std::fs::read_to_string(ZONE_TAB).ok()?;
    nearest_zone(&table, country, latitude, longitude)
}

/// The named zone, else the system zone, else UTC.
pub fn load(name: Option<&str>) -> TimeZone {
    name.and_then(|n| TimeZone::from_posix_tz(n).ok())
        .or_else(|| TimeZone::local().ok())
        .unwrap_or_else(TimeZone::utc)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TABLE: &str = "# comment\n\
        FI,AX\t+6010+02458\tEurope/Helsinki\n\
        US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)\n\
        US\t+340308-1181434\tAmerica/Los_Angeles\tPacific\n\
        CH,DE,LI\t+4723+00832\tEurope/Zurich\n";

    #[test]
    fn parses_coordinates() {
        let (lat, lon) = parse_iso6709("+404251-0740023").unwrap_or_default();
        assert!((lat - 40.714_167).abs() < 1e-4 && (lon + 74.006_389).abs() < 1e-4);
    }

    #[test]
    fn picks_the_nearest_zone_in_the_country() {
        let zone = |c, lat, lon| nearest_zone(TABLE, c, lat, lon);
        assert_eq!(
            zone("fi", 61.4981, 23.7608).as_deref(),
            Some("Europe/Helsinki")
        );
        assert_eq!(
            zone("us", 37.77, -122.42).as_deref(),
            Some("America/Los_Angeles")
        );
        assert_eq!(
            zone("us", 42.36, -71.06).as_deref(),
            Some("America/New_York")
        );
        assert_eq!(zone("de", 52.52, 13.40).as_deref(), Some("Europe/Zurich"));
        assert_eq!(zone("ie", 53.35, -6.26), None);
    }
}
