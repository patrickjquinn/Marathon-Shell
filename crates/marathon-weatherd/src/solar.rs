//! Sunrise, sunset and day/night from NOAA's general solar position
//! equations (gml.noaa.gov/grad/solcalc/solareqns.PDF), accurate to a minute
//! or two, which saves a Sunrise API call per forecast day.

use std::f64::consts::PI;

use tz::UtcDateTime;

/// Zenith of the sun's upper limb at the horizon, with refraction.
const HORIZON_ZENITH: f64 = 90.833;

/// Equation of time (minutes) and declination (radians) for a UTC instant.
fn sun_position(year_day: u16, hour: f64) -> (f64, f64) {
    let g = 2.0 * PI / 365.0 * (f64::from(year_day) + (hour - 12.0) / 24.0);
    let eqtime = 229.18
        * (0.000_075 + 0.001_868 * g.cos()
            - 0.032_077 * g.sin()
            - 0.014_615 * (2.0 * g).cos()
            - 0.040_849 * (2.0 * g).sin());
    let decl = 0.006_918 - 0.399_912 * g.cos() + 0.070_257 * g.sin() - 0.006_758 * (2.0 * g).cos()
        + 0.000_907 * (2.0 * g).sin()
        - 0.002_697 * (3.0 * g).cos()
        + 0.001_48 * (3.0 * g).sin();
    (eqtime, decl)
}

/// Sunrise and sunset (unix seconds) on the given calendar date at a place;
/// `None` for each when the sun doesn't cross the horizon that day.
pub fn sun_times(year: i32, month: u8, day: u8, lat: f64, lon: f64) -> (Option<i64>, Option<i64>) {
    let Ok(noon) = UtcDateTime::new(year, month, day, 12, 0, 0, 0) else {
        return (None, None);
    };
    let (eqtime, decl) = sun_position(noon.year_day(), 12.0);
    let lat = lat.to_radians();
    let cos_ha =
        HORIZON_ZENITH.to_radians().cos() / (lat.cos() * decl.cos()) - lat.tan() * decl.tan();
    if !(-1.0..=1.0).contains(&cos_ha) {
        return (None, None);
    }
    let ha = cos_ha.acos().to_degrees();
    let midnight = noon.unix_time() - 12 * 3600;
    let at = |minutes: f64| Some(midnight + seconds(minutes * 60.0));
    (
        at(720.0 - 4.0 * (lon + ha) - eqtime),
        at(720.0 - 4.0 * (lon - ha) - eqtime),
    )
}

/// Whether the sun's upper limb is above the horizon at a unix time.
pub fn is_day(unix: i64, lat: f64, lon: f64) -> bool {
    let Ok(t) = UtcDateTime::from_timespec(unix, 0) else {
        return true;
    };
    let hour = f64::from(t.hour()) + f64::from(t.minute()) / 60.0 + f64::from(t.second()) / 3600.0;
    let (eqtime, decl) = sun_position(t.year_day(), hour);
    let true_solar_minutes = hour * 60.0 + eqtime + 4.0 * lon;
    let ha = (true_solar_minutes / 4.0 - 180.0).to_radians();
    let lat = lat.to_radians();
    let cos_zenith = lat.sin() * decl.sin() + lat.cos() * decl.cos() * ha.cos();
    cos_zenith > HORIZON_ZENITH.to_radians().cos()
}

#[allow(
    clippy::cast_possible_truncation,
    reason = "a day's worth of seconds always fits"
)]
fn seconds(x: f64) -> i64 {
    x.round() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dublin_equinox_times_are_within_a_few_minutes_of_noaa() {
        // NOAA spreadsheet algorithm, Dublin 2026-03-20: sunrise 06:28, sunset 18:38 UTC.
        let (rise, set) = sun_times(2026, 3, 20, 53.3498, -6.2603);
        let midnight = 1_773_964_800;
        let rise = rise.map(|t| (t - midnight) / 60);
        let set = set.map(|t| (t - midnight) / 60);
        assert!(
            rise.is_some_and(|m| (m - (6 * 60 + 28)).abs() <= 3),
            "{rise:?}"
        );
        assert!(
            set.is_some_and(|m| (m - (18 * 60 + 38)).abs() <= 3),
            "{set:?}"
        );
    }

    #[test]
    fn polar_night_and_midnight_sun_have_no_times() {
        assert_eq!(sun_times(2026, 12, 21, 78.22, 15.65), (None, None));
        assert_eq!(sun_times(2026, 6, 21, 78.22, 15.65), (None, None));
    }

    #[test]
    fn day_and_night() {
        // Dublin, 2026-10-16 12:00 and 23:00 UTC.
        assert!(is_day(1_792_152_000, 53.35, -6.26));
        assert!(!is_day(1_792_191_600, 53.35, -6.26));
    }
}
