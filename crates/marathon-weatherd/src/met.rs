//! MET Norway Locationforecast 2.0 `complete` → the `Forecast` JSON the
//! shell reads (org.marathonos.Weather1). Metric units; a value MET doesn't
//! give is `null`.

use std::collections::BTreeMap;

use serde_json::{json, Value};
use tz::{DateTime, TimeZone, UtcDateTime};

use crate::solar;
use crate::store::Location;

const HOURLY_SPAN: i64 = 48 * 3600;
const MAX_DAYS: usize = 10;

/// MET's `symbol_code` without its `_day` / `_night` / `_polartwilight` suffix.
pub fn base_symbol(code: &str) -> &str {
    code.split('_').next().unwrap_or(code)
}

/// Orders symbols for the daily summary: precipitation over cloud, heavy
/// over light, thunder and snow over rain, steady over showers.
pub fn severity(symbol: &str) -> u32 {
    match symbol {
        "clearsky" => 0,
        "fair" => 1,
        "partlycloudy" => 2,
        "cloudy" => 3,
        "fog" => 4,
        s => {
            let mut n = if s.starts_with("light") {
                10
            } else if s.starts_with("heavy") {
                30
            } else {
                20
            };
            if s.contains("showers") {
                n -= 1;
            }
            if s.contains("snow") {
                n += 3;
            } else if s.contains("sleet") {
                n += 2;
            }
            if s.contains("thunder") {
                n += 5;
            }
            n
        }
    }
}

/// Australian Bureau of Meteorology apparent temperature (Steadman 1994,
/// shade, no radiation term): AT = Ta + 0.33·e − 0.70·ws − 4.00, with e the
/// water vapour pressure in hPa and ws the 10 m wind in m/s.
pub fn apparent_temperature(temperature: f64, humidity: f64, wind_speed: f64) -> f64 {
    let e = humidity / 100.0 * 6.105 * (17.27 * temperature / (237.7 + temperature)).exp();
    temperature + 0.33 * e - 0.70 * wind_speed - 4.00
}

/// `2026-10-16T22:00:00Z` → unix seconds.
pub fn parse_time(s: &str) -> Option<i64> {
    let n = |r: std::ops::Range<usize>| s.get(r)?.parse::<u8>().ok();
    let year = s.get(0..4)?.parse().ok()?;
    UtcDateTime::new(
        year,
        n(5..7)?,
        n(8..10)?,
        n(11..13)?,
        n(14..16)?,
        n(17..19)?,
        0,
    )
    .ok()
    .map(|t| t.unix_time())
}

fn r1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

#[allow(
    clippy::cast_possible_truncation,
    reason = "percentages and compass degrees"
)]
fn int(x: f64) -> i64 {
    x.round() as i64
}

fn fmax(a: Option<f64>, b: Option<f64>) -> Option<f64> {
    match (a, b) {
        (Some(a), Some(b)) => Some(a.max(b)),
        (a, b) => a.or(b),
    }
}

fn fmin(a: Option<f64>, b: Option<f64>) -> Option<f64> {
    match (a, b) {
        (Some(a), Some(b)) => Some(a.min(b)),
        (a, b) => a.or(b),
    }
}

struct Step<'a> {
    time: i64,
    data: &'a Value,
}

/// A `next_N_hours` block starting at its step's time.
struct Period<'a> {
    start: i64,
    hours: i64,
    block: &'a Value,
}

impl<'a> Step<'a> {
    fn instant(&self, key: &str) -> Option<f64> {
        self.data["instant"]["details"][key].as_f64()
    }

    fn period(&self, hours: i64) -> Option<Period<'a>> {
        let block = self.data.get(format!("next_{hours}_hours"))?;
        Some(Period {
            start: self.time,
            hours,
            block,
        })
    }

    /// The shortest period MET gives at this step.
    fn shortest(&self) -> Option<Period<'a>> {
        self.period(1).or_else(|| self.period(6))
    }

    fn apparent(&self) -> Option<f64> {
        Some(apparent_temperature(
            self.instant("air_temperature")?,
            self.instant("relative_humidity")?,
            self.instant("wind_speed")?,
        ))
    }
}

impl Period<'_> {
    fn symbol(&self) -> Option<&str> {
        self.block["summary"]["symbol_code"]
            .as_str()
            .map(base_symbol)
    }

    fn detail(&self, key: &str) -> Option<f64> {
        self.block["details"][key].as_f64()
    }
}

fn steps(met: &Value) -> Vec<Step<'_>> {
    met["properties"]["timeseries"]
        .as_array()
        .map(|series| {
            series
                .iter()
                .filter_map(|s| {
                    Some(Step {
                        time: parse_time(s["time"].as_str()?)?,
                        data: &s["data"],
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

type DayKey = (i32, u8, u8);

fn local(time: i64, tz: &TimeZone) -> Option<DateTime> {
    DateTime::from_timespec(time, 0, tz.as_ref()).ok()
}

fn day_key(t: &DateTime) -> DayKey {
    (t.year(), t.month(), t.month_day())
}

#[derive(Default)]
struct Day {
    high: Option<f64>,
    low: Option<f64>,
    precipitation: Option<f64>,
    probability: Option<f64>,
    wind_max: Option<f64>,
    uv_max: Option<f64>,
    /// (symbol, hours, mid-period falls in 06–18 local)
    symbols: Vec<(String, f64, bool)>,
}

impl Day {
    /// The most severe symbol that lasts at least three hours of the
    /// daytime, else the longest-lasting one.
    fn symbol(&self) -> Option<String> {
        let daytime = self.symbols.iter().any(|s| s.2);
        let mut totals: Vec<(&str, f64)> = Vec::new();
        for (symbol, hours, _) in self.symbols.iter().filter(|s| s.2 || !daytime) {
            match totals.iter_mut().find(|t| t.0 == symbol) {
                Some(t) => t.1 += hours,
                None => totals.push((symbol, *hours)),
            }
        }
        totals
            .iter()
            .filter(|t| t.1 >= 3.0)
            .max_by_key(|t| severity(t.0))
            .or_else(|| {
                totals.iter().max_by(|a, b| {
                    a.1.total_cmp(&b.1)
                        .then_with(|| severity(a.0).cmp(&severity(b.0)))
                })
            })
            .map(|t| t.0.to_owned())
    }
}

fn daily(steps: &[Step], loc: &Location, tz: &TimeZone, today: DayKey) -> Vec<Value> {
    let mut days: BTreeMap<DayKey, Day> = BTreeMap::new();
    // Hourly blocks overlap the 6-hour ones; count each hour of
    // precipitation and weather once.
    let mut covered_until = i64::MIN;
    for step in steps {
        let Some(t) = local(step.time, tz) else {
            continue;
        };
        let day = days.entry(day_key(&t)).or_default();
        let temperature = step.instant("air_temperature");
        day.high = fmax(day.high, temperature);
        day.low = fmin(day.low, temperature);
        day.wind_max = fmax(day.wind_max, step.instant("wind_speed"));
        day.uv_max = fmax(day.uv_max, step.instant("ultraviolet_index_clear_sky"));

        let Some(period) = step.shortest().filter(|_| step.time >= covered_until) else {
            continue;
        };
        covered_until = period.start + period.hours * 3600;
        if period.hours > 1 {
            day.high = fmax(day.high, period.detail("air_temperature_max"));
            day.low = fmin(day.low, period.detail("air_temperature_min"));
        }
        if let Some(amount) = period.detail("precipitation_amount") {
            day.precipitation = Some(day.precipitation.unwrap_or(0.0) + amount);
        }
        day.probability = fmax(
            day.probability,
            period.detail("probability_of_precipitation"),
        );
        if let Some(symbol) = period.symbol() {
            let mid = local(period.start + period.hours * 1800, tz).map_or(0, |m| m.hour());
            #[allow(clippy::cast_precision_loss, reason = "1 or 6")]
            let hours = period.hours as f64;
            day.symbols
                .push((symbol.to_owned(), hours, (6..18).contains(&mid)));
        }
    }
    days.range(today..)
        .take(MAX_DAYS)
        .map(|(&(y, m, d), day)| {
            let (sunrise, sunset) = solar::sun_times(y, m, d, loc.latitude, loc.longitude);
            json!({
                "date": format!("{y:04}-{m:02}-{d:02}"),
                "high": day.high.map(r1),
                "low": day.low.map(r1),
                "symbol": day.symbol(),
                "precipitation": day.precipitation.map(r1),
                "precipitation_probability": day.probability.map(int),
                "wind_speed_max": day.wind_max.map(r1),
                "uv_max": day.uv_max.map(r1),
                "sunrise": sunrise,
                "sunset": sunset,
            })
        })
        .collect()
}

fn current(step: &Step) -> Value {
    let hour = step.period(1);
    let hour_detail = |key| hour.as_ref().and_then(|p| p.detail(key));
    json!({
        "time": step.time,
        "temperature": step.instant("air_temperature").map(r1),
        "apparent": step.apparent().map(r1),
        "symbol": step.shortest().as_ref().and_then(Period::symbol),
        "wind_speed": step.instant("wind_speed").map(r1),
        "wind_gust": step.instant("wind_speed_of_gust").map(r1),
        "wind_direction": step.instant("wind_from_direction").map(int),
        "humidity": step.instant("relative_humidity").map(int),
        "pressure": step.instant("air_pressure_at_sea_level").map(r1),
        "uv_index": step.instant("ultraviolet_index_clear_sky").map(r1),
        "cloud_cover": step.instant("cloud_area_fraction").map(int),
        "precipitation_1h": hour_detail("precipitation_amount").map(r1),
        "precipitation_probability": hour_detail("probability_of_precipitation").map(int),
        "dew_point": step.instant("dew_point_temperature").map(r1),
    })
}

fn hourly(step: &Step, loc: &Location) -> Value {
    let period = step.shortest();
    let detail = |key| period.as_ref().and_then(|p| p.detail(key));
    json!({
        "time": step.time,
        "temperature": step.instant("air_temperature").map(r1),
        "symbol": period.as_ref().and_then(Period::symbol),
        "precipitation": detail("precipitation_amount").map(r1),
        "precipitation_probability": detail("probability_of_precipitation").map(int),
        "wind_speed": step.instant("wind_speed").map(r1),
        "wind_direction": step.instant("wind_from_direction").map(int),
        "is_day": solar::is_day(step.time, loc.latitude, loc.longitude),
    })
}

/// The forecast as seen at `now`, or `None` when the data has run out.
pub fn forecast(
    met: &Value,
    loc: &Location,
    automatic: bool,
    tz: &TimeZone,
    now: i64,
) -> Option<Value> {
    let steps = steps(met);
    let current_index = steps
        .iter()
        .rposition(|s| s.time <= now)
        .unwrap_or_default();
    let now_step = steps.get(current_index)?;
    let valid_for = now_step.shortest().map_or(3600, |p| p.hours * 3600);
    if now >= now_step.time + valid_for {
        return None;
    }
    let today = day_key(&local(now, tz)?);
    let hours: Vec<Value> = steps[current_index + 1..]
        .iter()
        .take_while(|s| s.time <= now_step.time + HOURLY_SPAN)
        .map(|s| hourly(s, loc))
        .collect();
    let updated = met["properties"]["meta"]["updated_at"]
        .as_str()
        .and_then(parse_time);
    Some(json!({
        "location": {
            "name": loc.name,
            "region": loc.region,
            "latitude": (loc.latitude * 10_000.0).round() / 10_000.0,
            "longitude": (loc.longitude * 10_000.0).round() / 10_000.0,
            "automatic": automatic,
        },
        "updated": updated,
        "attribution": "MET Norway",
        "timezone_offset": local(now, tz).map(|t| t.local_time_type().ut_offset()),
        "current": current(now_step),
        "hourly": hours,
        "daily": daily(&steps, loc, tz, today),
    }))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::float_cmp, reason = "tests")]
mod tests {
    use super::*;

    fn fixture() -> Value {
        let path = format!(
            "{}/tests/fixtures/met-tampere.json",
            env!("CARGO_MANIFEST_DIR")
        );
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    fn tampere() -> Location {
        Location {
            name: "Tampere".into(),
            region: "Pirkanmaa, Finland".into(),
            latitude: 61.4981,
            longitude: 23.7608,
        }
    }

    /// Europe/Helsinki in October, without depending on the host's tzdata.
    fn eest() -> TimeZone {
        TimeZone::fixed(3 * 3600).unwrap()
    }

    // 2026-10-16T22:10:00Z, ten minutes after the fixture's first step.
    const NOW: i64 = 1_792_188_600;

    #[test]
    fn strips_symbol_suffixes() {
        assert_eq!(base_symbol("clearsky_day"), "clearsky");
        assert_eq!(
            base_symbol("lightrainshowers_polartwilight"),
            "lightrainshowers"
        );
        assert_eq!(base_symbol("fair_night"), "fair");
        assert_eq!(base_symbol("rainandthunder"), "rainandthunder");
    }

    #[test]
    fn severity_orders_symbols() {
        assert!(severity("cloudy") < severity("lightrain"));
        assert!(severity("lightrainshowers") < severity("lightrain"));
        assert!(severity("lightsnowandthunder") < severity("rainshowers"));
        assert!(severity("rain") < severity("snow"));
        assert!(severity("heavyrain") < severity("heavyrainandthunder"));
    }

    #[test]
    fn apparent_temperature_matches_bom() {
        // 20 °C, 50 %, 5 m/s: e = 11.66 hPa → 20 + 3.85 − 3.5 − 4 = 16.35 °C.
        assert!((apparent_temperature(20.0, 50.0, 5.0) - 16.35).abs() < 0.01);
        // Cold, wet and windy feels colder; calm humid heat feels hotter.
        assert!(apparent_temperature(2.0, 87.0, 4.0) < 2.0);
        assert!(apparent_temperature(30.0, 80.0, 0.0) > 30.0);
    }

    #[test]
    fn parses_met_times() {
        assert_eq!(parse_time("2026-10-16T22:00:00Z"), Some(1_792_188_000));
        assert_eq!(parse_time("2026-13-16T22:00:00Z"), None);
        assert_eq!(parse_time("nonsense"), None);
    }

    #[test]
    fn maps_the_fixture_to_the_contract() {
        let f = forecast(&fixture(), &tampere(), true, &eest(), NOW).unwrap();
        assert_eq!(f["location"]["name"], "Tampere");
        assert_eq!(f["location"]["automatic"], true);
        assert_eq!(f["attribution"], "MET Norway");
        assert_eq!(f["timezone_offset"], 10800);
        assert_eq!(f["updated"], parse_time("2026-10-16T21:29:37Z").unwrap());

        let c = &f["current"];
        assert_eq!(c["time"], 1_792_188_000);
        assert_eq!(c["temperature"], 11.6);
        assert_eq!(c["symbol"], "lightrain");
        assert_eq!(c["wind_speed"], 2.9);
        assert_eq!(c["wind_gust"], 5.4);
        assert_eq!(c["wind_direction"], 185);
        assert_eq!(c["humidity"], 97);
        assert_eq!(c["pressure"], 1014.7);
        assert_eq!(c["cloud_cover"], 100);
        assert_eq!(c["precipitation_1h"], 0.1);
        assert_eq!(c["precipitation_probability"], 58);
        assert_eq!(c["dew_point"], 11.3);
        let apparent = c["apparent"].as_f64().unwrap();
        assert!(apparent < 11.6 && apparent > 5.0, "{apparent}");

        let hourly = f["hourly"].as_array().unwrap();
        assert_eq!(hourly.len(), 48);
        assert_eq!(hourly[0]["time"], 1_792_188_000 + 3600);
        assert!(hourly
            .windows(2)
            .all(|w| w[1]["time"].as_i64().unwrap() - w[0]["time"].as_i64().unwrap() == 3600));
        assert!(hourly
            .iter()
            .all(|h| !h["symbol"].as_str().unwrap().contains('_')));
        assert_eq!(hourly[0]["is_day"], false);
        // 2026-10-17T10:00Z is midday in Tampere.
        let midday = hourly.iter().find(|h| h["time"] == 1_792_231_200).unwrap();
        assert_eq!(midday["is_day"], true);
    }

    #[test]
    fn days_follow_local_midnight() {
        let f = forecast(&fixture(), &tampere(), true, &eest(), NOW).unwrap();
        let days = f["daily"].as_array().unwrap();
        // 22:10Z is already the 17th in Helsinki, so the 16th is gone.
        assert_eq!(days[0]["date"], "2026-10-17");
        assert!(days.len() >= 9 && days.len() <= MAX_DAYS, "{}", days.len());
        for d in days {
            assert!(d["high"].as_f64().unwrap() >= d["low"].as_f64().unwrap());
            assert!(!d["symbol"].as_str().unwrap().contains('_'));
            assert!(d["sunrise"].as_i64().unwrap() < d["sunset"].as_i64().unwrap());
        }

        // In UTC the same instant is still the 16th: a two-hour day whose
        // values come only from the 22:00 and 23:00 steps.
        let utc = forecast(&fixture(), &tampere(), true, &TimeZone::utc(), NOW).unwrap();
        let first = &utc["daily"][0];
        assert_eq!(first["date"], "2026-10-16");
        assert_eq!(first["high"], 11.6);
        assert_eq!(first["precipitation"], 0.6);
        assert_eq!(first["precipitation_probability"], 83);
        assert_eq!(utc["daily"][1]["date"], "2026-10-17");
    }

    #[test]
    fn daytime_symbol_prefers_lasting_severe_weather() {
        let day = Day {
            symbols: vec![
                ("cloudy".into(), 8.0, true),
                ("lightrain".into(), 3.0, true),
                ("heavyrain".into(), 1.0, true),
                ("snow".into(), 6.0, false),
            ],
            ..Day::default()
        };
        assert_eq!(day.symbol().as_deref(), Some("lightrain"));
        let night_only = Day {
            symbols: vec![("fair".into(), 2.0, false), ("cloudy".into(), 1.0, false)],
            ..Day::default()
        };
        assert_eq!(night_only.symbol().as_deref(), Some("fair"));
    }

    #[test]
    fn stale_data_gives_no_forecast() {
        assert!(forecast(&fixture(), &tampere(), true, &eest(), NOW + 30 * 86_400).is_none());
        assert!(forecast(&json!({}), &tampere(), true, &eest(), NOW).is_none());
    }
}
