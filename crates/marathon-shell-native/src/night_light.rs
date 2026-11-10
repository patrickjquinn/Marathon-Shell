//! When the night light's schedule has it on: from sunset to sunrise where
//! the time zone's principal city is, or between two local times. Like
//! Android's, a schedule turns it on or off at its edges and a toggle in
//! between holds until the next edge.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_channel::Receiver;
use tz::{DateTime, TimeZone, TimeZoneRef};

use crate::display::qobject::Display;
use crate::io;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Schedule {
    Manual,
    /// Sunset to sunrise where the local time zone is.
    Sunset,
    /// Sunset to sunrise at this latitude and longitude, in degrees.
    Sun(f64, f64),
    /// From and to, in minutes after local midnight.
    Times(i32, i32),
}

pub enum Plan {
    /// A new schedule, applied at once.
    Set(Schedule),
    /// The screen came on: suspended time doesn't count on the timer.
    Check,
}

/// Whether the schedule has the light on at `now` (Unix seconds), and when
/// that next changes.
pub fn state(schedule: Schedule, now: i64, zone: TimeZoneRef<'_>) -> Option<(bool, i64)> {
    let day = now.div_euclid(86_400);
    let nights: Vec<(i64, i64)> = (day - 2..=day + 2)
        .filter_map(|d| match schedule {
            Schedule::Manual | Schedule::Sunset => None,
            Schedule::Sun(lat, lon) => Some((sun(d, lat, lon)?.1, sun(d + 1, lat, lon)?.0)),
            Schedule::Times(from, to) if from == to => None,
            Schedule::Times(from, to) => {
                let to_day = if to < from { d + 1 } else { d };
                Some((local(d, from, zone)?, local(to_day, to, zone)?))
            }
        })
        .collect();
    let on = nights.iter().any(|&(start, end)| start <= now && now < end);
    let next = nights
        .iter()
        .flat_map(|&(start, end)| [start, end])
        .filter(|&t| t > now)
        .min()?;
    Some((on, next))
}

/// `minutes` after midnight on the local date of day `day` (days since the
/// epoch, taken at noon so the zone's offset can't move the date).
fn local(day: i64, minutes: i32, zone: TimeZoneRef<'_>) -> Option<i64> {
    let date = DateTime::from_timespec(day * 86_400 + 43_200, 0, zone).ok()?;
    let (h, m) = (minutes.div_euclid(60), minutes.rem_euclid(60));
    let found = DateTime::find(
        date.year(),
        date.month(),
        date.month_day(),
        u8::try_from(h).ok()?,
        u8::try_from(m).ok()?,
        0,
        0,
        zone,
    )
    .ok()?;
    Some(found.earliest().or_else(|| found.latest())?.unix_time())
}

/// Sunrise and sunset on day `day` (days since the epoch) at `lat`, `lon`
/// (east positive), as Unix seconds; `None` in a polar day or night. The
/// NOAA approximation, good to about a minute.
fn sun(day: i64, lat: f64, lon: f64) -> Option<(i64, i64)> {
    #[allow(clippy::cast_precision_loss, reason = "days since 2000")]
    let noon = (day - 10_957) as f64 - lon / 360.0;
    let anomaly = (357.5291 + 0.985_600_28 * noon)
        .rem_euclid(360.0)
        .to_radians();
    let centre =
        1.9148 * anomaly.sin() + 0.02 * (2.0 * anomaly).sin() + 0.0003 * (3.0 * anomaly).sin();
    let ecliptic = (anomaly.to_degrees() + centre + 180.0 + 102.9372)
        .rem_euclid(360.0)
        .to_radians();
    let transit = noon + 0.0053 * anomaly.sin() - 0.0069 * (2.0 * ecliptic).sin();
    let declination = (ecliptic.sin() * 23.4397_f64.to_radians().sin()).asin();
    let latitude = lat.to_radians();
    let cos_hour = ((-0.833_f64).to_radians().sin() - latitude.sin() * declination.sin())
        / (latitude.cos() * declination.cos());
    if !(-1.0..=1.0).contains(&cos_hour) {
        return None;
    }
    let half_day = cos_hour.acos().to_degrees() / 360.0;
    #[allow(clippy::cast_possible_truncation, reason = "seconds of a date")]
    let unix = |days_since_2000: f64| ((days_since_2000 + 10_957.5) * 86_400.0).round() as i64;
    Some((unix(transit - half_day), unix(transit + half_day)))
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX))
}

/// Turns the light on and off at the schedule's edges.
pub async fn run(qt: cxx_qt::CxxQtThread<Display>, plans: Receiver<Plan>) {
    let mut schedule = Schedule::Manual;
    let mut edge: Option<i64> = None;
    loop {
        let wait = edge.map(|e| Duration::from_secs(u64::try_from(e - now()).unwrap_or(0)));
        let set = match io::recv_within(&plans, wait).await {
            Some(Err(_)) => return,
            Some(Ok(Plan::Set(s))) => {
                schedule = s;
                true
            }
            Some(Ok(Plan::Check)) | None => false,
        };
        let at = now();
        if !set && edge.is_none_or(|e| at < e) {
            continue;
        }
        let (zone, place) = blocking::unblock(|| {
            (
                TimeZone::local().ok(),
                crate::timezone::place(&marathon_rt::units::local_zone()),
            )
        })
        .await;
        let resolved = match (schedule, place) {
            (Schedule::Sunset, Some((lat, lon))) => Schedule::Sun(lat, lon),
            (s, _) => s,
        };
        let Some((on, next)) = zone.and_then(|z| state(resolved, at, z.as_ref())) else {
            edge = None;
            continue;
        };
        edge = Some(next);
        qt.queue(move |obj| obj.set_night_light_enabled(on)).ok();
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use tz::UtcDateTime;

    use super::*;

    fn utc(y: i32, mo: u8, d: u8, h: u8, mi: u8) -> i64 {
        UtcDateTime::new(y, mo, d, h, mi, 0, 0).unwrap().unix_time()
    }

    const DUBLIN: (f64, f64) = (53.333, -6.25);

    #[test]
    fn dublin_sunset_and_sunrise_are_within_minutes_of_the_almanac() {
        // 2026-06-21: sunrise 04:57, sunset 21:57 IST (03:57, 20:57 UTC).
        let (rise, set) = sun(utc(2026, 6, 21, 12, 0) / 86_400, DUBLIN.0, DUBLIN.1).unwrap();
        assert!((rise - utc(2026, 6, 21, 3, 57)).abs() < 300, "{rise}");
        assert!((set - utc(2026, 6, 21, 20, 57)).abs() < 300, "{set}");
    }

    #[test]
    fn the_sun_schedule_is_on_at_night_and_off_by_day() {
        let utc_zone = TimeZone::utc();
        let schedule = Schedule::Sun(DUBLIN.0, DUBLIN.1);
        let (on, next) = state(schedule, utc(2026, 6, 21, 23, 0), utc_zone.as_ref()).unwrap();
        assert!(on);
        assert!((next - utc(2026, 6, 22, 3, 57)).abs() < 300);
        let (on, next) = state(schedule, utc(2026, 6, 21, 12, 0), utc_zone.as_ref()).unwrap();
        assert!(!on);
        assert!((next - utc(2026, 6, 21, 20, 57)).abs() < 300);
    }

    #[test]
    fn times_across_midnight_hold_until_the_morning() {
        let zone = TimeZone::from_posix_tz("CET-1").unwrap();
        let schedule = Schedule::Times(22 * 60, 7 * 60);
        // 23:30 local is 22:30 UTC.
        let (on, next) = state(schedule, utc(2026, 7, 1, 22, 30), zone.as_ref()).unwrap();
        assert!(on);
        assert_eq!(next, utc(2026, 7, 2, 6, 0));
        let (on, next) = state(schedule, utc(2026, 7, 2, 6, 0), zone.as_ref()).unwrap();
        assert!(!on);
        assert_eq!(next, utc(2026, 7, 2, 21, 0));
    }

    #[test]
    fn times_within_a_day_and_empty_ranges() {
        let utc_zone = TimeZone::utc();
        let schedule = Schedule::Times(13 * 60, 14 * 60);
        assert_eq!(
            state(schedule, utc(2026, 1, 5, 13, 30), utc_zone.as_ref()),
            Some((true, utc(2026, 1, 5, 14, 0)))
        );
        assert_eq!(state(Schedule::Times(60, 60), 0, utc_zone.as_ref()), None);
        assert_eq!(state(Schedule::Manual, 0, utc_zone.as_ref()), None);
    }

    #[test]
    fn no_sunset_in_the_polar_summer() {
        assert_eq!(sun(utc(2026, 6, 21, 12, 0) / 86_400, 78.2, 15.6), None);
    }
}
