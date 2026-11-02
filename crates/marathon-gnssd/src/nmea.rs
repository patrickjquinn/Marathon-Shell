//! NMEA 0183 GGA and RMC sentences for the `GeoClue` `nmea-socket` source.

fn sentence(body: &str) -> String {
    let sum = body.bytes().fold(0u8, |s, b| s ^ b);
    format!("${body}*{sum:02X}\r\n")
}

fn angle(v: f64, pos: char, neg: char, deg_digits: usize) -> String {
    let a = v.abs();
    let deg = a.trunc();
    let min = (a - deg) * 60.0;
    format!(
        "{deg:0deg_digits$}{min:07.4},{}",
        if v < 0.0 { neg } else { pos }
    )
}

/// UTC as (hhmmss.ss, ddmmyy).
pub struct Utc {
    pub time: String,
    pub date: String,
}

pub fn gga(utc: &Utc, lat: f64, lon: f64, alt: f64, sats: usize, hdop: f64) -> String {
    sentence(&format!(
        "GPGGA,{},{},{},1,{sats:02},{hdop:.1},{alt:.1},M,,M,,",
        utc.time,
        angle(lat, 'N', 'S', 2),
        angle(lon, 'E', 'W', 3)
    ))
}

pub fn rmc(utc: &Utc, lat: f64, lon: f64) -> String {
    sentence(&format!(
        "GPRMC,{},A,{},{},0.0,0.0,{},,,A",
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
        let s = gga(&utc, 53.343_9, -6.267_3, 21.5, 7, 1.2);
        assert_eq!(
            s,
            "$GPGGA,123519.00,5320.6340,N,00616.0380,W,1,07,1.2,21.5,M,,M,,*50\r\n"
        );
        assert!(rmc(&utc, 53.343_9, -6.267_3)
            .starts_with("$GPRMC,123519.00,A,5320.6340,N,00616.0380,W,"));
    }
}
