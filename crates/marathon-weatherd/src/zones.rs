//! A place's time zone, from its coordinates, with tzf-rs's bundled zone
//! boundaries.

use tz::TimeZone;
use tzf_rs::DefaultFinder;

pub struct Zones(DefaultFinder);

impl Zones {
    pub fn new() -> Self {
        Self(DefaultFinder::new())
    }

    /// The zone at a point, else the system zone, else UTC.
    pub fn at(&self, latitude: f64, longitude: f64) -> TimeZone {
        Some(self.0.get_tz_name(longitude, latitude))
            .filter(|name| !name.is_empty())
            .and_then(|name| TimeZone::from_posix_tz(name).ok())
            .or_else(|| TimeZone::local().ok())
            .unwrap_or_else(TimeZone::utc)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offset(zones: &Zones, latitude: f64, longitude: f64) -> i32 {
        // 2026-10-16 12:00 UTC.
        zones
            .at(latitude, longitude)
            .find_local_time_type(1_792_152_000)
            .map(tz::LocalTimeType::ut_offset)
            .unwrap_or_default()
    }

    #[test]
    fn zones_follow_the_coordinates() {
        let zones = Zones::new();
        assert_eq!(offset(&zones, 53.35, -6.26), 3600, "Dublin, summer time");
        assert_eq!(offset(&zones, 61.50, 23.76), 3 * 3600, "Tampere");
        assert_eq!(offset(&zones, 37.77, -122.42), -7 * 3600, "San Francisco");
        assert_eq!(offset(&zones, 42.36, -71.06), -4 * 3600, "Boston");
    }
}
