//! NMEA 0183 GGA and RMC sentences for the `GeoClue` `nmea-socket` source.

fn sentence(body: &str) -> String {
    let sum = body.bytes().fold(0u8, |s, b| s ^ b);
    format!("${body}*{sum:02X}\r\n")
}

fn angle(v: f64, pos: char, neg: char, deg_digits: usize) -> String {
    // Whole 1e-4 minutes first, so that 59.99996' never prints as 60.0000'.
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "angles fit"
    )]
    let units = (v.abs() * 600_000.0).round() as u64;
    let (deg, min) = (units / 600_000, units % 600_000);
    format!(
        "{deg:0deg_digits$}{:02}.{:04},{}",
        min / 10_000,
        min % 10_000,
        if v < 0.0 { neg } else { pos }
    )
}

/// UTC as (hhmmss.ss, ddmmyy).
pub struct Utc {
    pub time: String,
    pub date: String,
}

/// GGA; `msl` is the height above mean sea level, `geoid` the geoid height
/// above the ellipsoid.
pub fn gga(utc: &Utc, lat: f64, lon: f64, msl: f64, geoid: f64, sats: usize, hdop: f64) -> String {
    sentence(&format!(
        "GNGGA,{},{},{},1,{sats:02},{hdop:.1},{msl:.1},M,{geoid:.1},M,,",
        utc.time,
        angle(lat, 'N', 'S', 2),
        angle(lon, 'E', 'W', 3)
    ))
}

pub fn rmc(utc: &Utc, lat: f64, lon: f64) -> String {
    sentence(&format!(
        "GNRMC,{},A,{},{},0.0,0.0,{},,,A",
        utc.time,
        angle(lat, 'N', 'S', 2),
        angle(lon, 'E', 'W', 3),
        utc.date
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gga_format_and_checksum() {
        let utc = Utc {
            time: "123519.00".into(),
            date: "021126".into(),
        };
        let s = gga(&utc, 53.343_9, -6.267_3, 40.2, 54.7, 7, 1.2);
        assert_eq!(
            s,
            "$GNGGA,123519.00,5320.6340,N,00616.0380,W,1,07,1.2,40.2,M,54.7,M,,*56\r\n"
        );
        assert!(rmc(&utc, 53.343_9, -6.267_3)
            .starts_with("$GNRMC,123519.00,A,5320.6340,N,00616.0380,W,"));
        // 59.99999' rounds into the next whole degree.
        assert!(gga(&utc, 53.999_999_9, 0.0, 0.0, 0.0, 4, 1.0).contains(",5400.0000,N,"));
    }
}
