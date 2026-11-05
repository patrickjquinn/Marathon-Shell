//! A first guess at the receiver's whereabouts: the principal location of
//! the system time zone, from the tz database's `zone1970.tab`.

/// Latitude and longitude (degrees) of `zone` in a `zone1970.tab` text.
pub fn position(table: &str, zone: &str) -> Option<(f64, f64)> {
    let line = table
        .lines()
        .filter(|l| !l.starts_with('#'))
        .find(|l| l.split('\t').nth(2) == Some(zone))?;
    coordinates(line.split('\t').nth(1)?)
}

/// ISO 6709 `±DDMM±DDDMM` or `±DDMMSS±DDDMMSS`.
fn coordinates(s: &str) -> Option<(f64, f64)> {
    let split = s[1..].find(['+', '-'])? + 1;
    Some((angle(&s[..split], 2)?, angle(&s[split..], 3)?))
}

fn angle(s: &str, degree_digits: usize) -> Option<f64> {
    let sign = if s.starts_with('-') { -1.0 } else { 1.0 };
    let d = &s[1..];
    let part = |from: usize, len: usize| -> Option<f64> { d.get(from..from + len)?.parse().ok() };
    let deg = part(0, degree_digits)?;
    let min = part(degree_digits, 2)?;
    let sec = part(degree_digits + 2, 2).unwrap_or(0.0);
    Some(sign * (deg + min / 60.0 + sec / 3600.0))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    const TABLE: &str = "# comment\n\
        IE\t+5320-00615\tEurope/Dublin\n\
        US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)\n";

    #[test]
    fn finds_zones() {
        let (lat, lon) = position(TABLE, "Europe/Dublin").unwrap();
        assert!((lat - 53.333).abs() < 1e-3 && (lon + 6.25).abs() < 1e-3);
        let (lat, lon) = position(TABLE, "America/New_York").unwrap();
        assert!((lat - 40.714).abs() < 1e-3 && (lon + 74.006).abs() < 1e-3);
        assert!(position(TABLE, "Europe/Paris").is_none());
    }
}
