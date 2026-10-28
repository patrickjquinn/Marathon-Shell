// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! `weather.forecast`: current weather and the forecast from Open-Meteo
//! (open data from national weather services, no key, no account). Web
//! pages are no source for weather: their snippets are hours old, and
//! Pilot told the person it was 6 °C and overcast in Dublin when it was
//! 12.8 °C and clear, then made up "tomorrow" from them.
//!
//! Only a place name leaves the phone: the one asked about, or the time
//! zone's city (Europe/Dublin: Dublin) when none is given. Both calls are
//! logged as egress like any other.

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::{json, Value};

use crate::remote::Remote;
use crate::schema::Validator;
use crate::tools::{Confirm, Registry, ToolError, ToolExecutor, ToolOutput, ToolSpec};

pub const TOOL: &str = "weather.forecast";
const GEOCODE: &str = "https://geocoding-api.open-meteo.com/v1/search";
const FORECAST: &str = "https://api.open-meteo.com/v1/forecast";

pub struct Weather {
    pub remote: Remote,
    /// What the person asked Pilot to remember: where they live ("I live
    /// in Galway") is the place when none is named.
    pub store: Option<Arc<crate::store::Store>>,
}

/// The town in a remembered fact about home ("I live in Galway", "we
/// moved from Cork to Galway last month" -> "Galway").
pub fn home_from_fact(fact: &str) -> Option<String> {
    let l = fact.to_ascii_lowercase();
    if !(l.contains("live") || l.contains("moved")) {
        return None;
    }
    let at = ["live in ", "moved to ", " to "]
        .iter()
        .find_map(|k| l.rfind(k).map(|i| i + k.len()))?;
    let place: String = fact[at..]
        .split([',', '.', ';', '!'])
        .next()?
        .split_whitespace()
        .take_while(|w| w.chars().next().is_some_and(char::is_uppercase))
        .collect::<Vec<_>>()
        .join(" ");
    (place.chars().count() >= 2).then_some(place)
}

/// The tool's declaration.
///
/// # Panics
///
/// Never: the schema is static and valid.
pub fn spec() -> ToolSpec {
    ToolSpec {
        name: TOOL.into(),
        title: "Weather".into(),
        description: "The weather now, hour by hour for the next day, and day by day for up \
                      to ten days, from a weather service. Use it for every question about \
                      weather, temperature, rain, wind or what to wear, follow-ups included \
                      (\"and tomorrow?\" calls it again for that day). Never answer weather \
                      from memory, earlier answers or web pages. Leave place out for where \
                      the person is."
            .into(),
        input: Validator::new(json!({"type": "object", "properties": {
            "place": {"type": "string", "minLength": 2, "maxLength": 100,
                      "description": "A town or city, only when the person names one"},
            "days": {"type": "integer", "minimum": 1, "maximum": 10,
                     "description": "Days of forecast from today (default 3); enough to reach the day asked about (next weekend from a Sunday is 8)"}},
            "additionalProperties": false}))
        .expect("static schema"),
        output: None,
        confirm: Confirm::Never,
        read_only: true,
        destructive: false,
        open_world: false,
        domain: "weather".into(),
    }
}

/// Adds `weather.forecast`.
pub fn register(registry: &mut Registry, remote: Remote, store: Option<Arc<crate::store::Store>>) {
    registry.add(spec(), true, Arc::new(Weather { remote, store }));
}

/// WMO weather code, in words.
pub fn describe(code: i64) -> &'static str {
    match code {
        0 => "clear",
        1 => "mainly clear",
        2 => "partly cloudy",
        3 => "overcast",
        45 | 48 => "fog",
        51 | 53 | 55 => "drizzle",
        56 | 57 => "freezing drizzle",
        61 => "light rain",
        63 => "rain",
        65 => "heavy rain",
        66 | 67 => "freezing rain",
        71 | 73 | 75 | 77 => "snow",
        80 => "light showers",
        81 => "showers",
        82 => "heavy showers",
        85 | 86 => "snow showers",
        95 => "thunderstorms",
        96 | 99 => "thunderstorms with hail",
        _ => "unknown",
    }
}

/// Percent-encoding for a query value.
fn enc(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                (b as char).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn num(v: &Value, k: &str) -> Option<f64> {
    v.get(k).and_then(Value::as_f64)
}

/// The weekday of an ISO date ("2026-10-17" → "Saturday"): the model
/// miscounted days from dates ("the weekend" on a Sunday).
fn weekday(date: &str) -> Option<&'static str> {
    let mut parts = date.split('-').map(|p| p.parse::<i64>().ok());
    let (year, month, day) = (parts.next()??, parts.next()??, parts.next()??);
    // Sakamoto's method; 0 is Sunday.
    let offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
    let year = if month < 3 { year - 1 } else { year };
    let offset = offsets.get(usize::try_from(month - 1).ok()?)?;
    let w = (year + year / 4 - year / 100 + year / 400 + offset + day).rem_euclid(7);
    Some(
        [
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
        ][usize::try_from(w).ok()?],
    )
}

/// The units a forecast is asked for and named in: metric, or (the
/// United States, Liberia and Myanmar) Fahrenheit, mph and inches, so the
/// model answers in the units the person uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Units {
    pub imperial: bool,
}

impl Units {
    pub fn for_locale(locale: &crate::lang::Locale) -> Units {
        Units {
            imperial: locale.imperial(),
        }
    }

    /// Open-Meteo's unit parameters (none for its metric default).
    fn query(self) -> &'static str {
        if self.imperial {
            "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch"
        } else {
            ""
        }
    }

    /// `name` with its unit: `temp` -> `temp_c` or `temp_f`.
    fn key(self, name: &str) -> String {
        let unit = match (name, self.imperial) {
            ("wind", false) => "kmh",
            ("wind", true) => "mph",
            ("rain", false) => "mm",
            ("rain", true) => "in",
            (_, false) => "c",
            (_, true) => "f",
        };
        format!("{name}_{unit}")
    }
}

/// The model's view of a forecast reply: the place, now, the next 24 hours
/// every 3 hours, and each day, in `units`.
pub fn summarise(place: &str, f: &Value, units: Units) -> Value {
    let k = |name: &str| units.key(name);
    let cur = &f["current"];
    let round = |x: Option<f64>| x.map(|v| (v * 10.0).round() / 10.0);
    let code = |v: Option<&Value>| v.and_then(Value::as_i64).map_or("unknown", describe);
    let hourly = &f["hourly"];
    let hours: Vec<Value> = hourly["time"]
        .as_array()
        .map(|t| {
            t.iter()
                .enumerate()
                .step_by(3)
                .map(|(i, time)| {
                    let mut h = json!({
                        "time": time,
                        "rain_chance_pct": hourly["precipitation_probability"].get(i),
                        "sky": code(hourly["weather_code"].get(i)),
                    });
                    h[k("temp")] = json!(round(
                        hourly["temperature_2m"].get(i).and_then(Value::as_f64)
                    ));
                    h
                })
                .collect()
        })
        .unwrap_or_default();
    let daily = &f["daily"];
    let days: Vec<Value> = daily["time"]
        .as_array()
        .map(|t| {
            t.iter()
                .enumerate()
                .map(|(i, date)| {
                    let mut d = json!({
                        "date": date,
                        "day": date.as_str().and_then(weekday),
                        "weekend": date
                            .as_str()
                            .and_then(weekday)
                            .is_some_and(|d| d == "Saturday" || d == "Sunday"),
                        "rain_chance_pct": daily["precipitation_probability_max"].get(i),
                        "sky": code(daily["weather_code"].get(i)),
                    });
                    d[k("min")] = json!(round(
                        daily["temperature_2m_min"].get(i).and_then(Value::as_f64)
                    ));
                    d[k("max")] = json!(round(
                        daily["temperature_2m_max"].get(i).and_then(Value::as_f64)
                    ));
                    d
                })
                .collect()
        })
        .unwrap_or_default();
    let mut now = json!({
        "time": cur.get("time"),
        "sky": code(cur.get("weather_code")),
        "humidity_pct": cur.get("relative_humidity_2m"),
    });
    now[k("temp")] = json!(round(num(cur, "temperature_2m")));
    now[k("feels_like")] = json!(round(num(cur, "apparent_temperature")));
    now[k("wind")] = json!(round(num(cur, "wind_speed_10m")));
    now[k("rain")] = json!(cur.get("precipitation"));
    json!({
        "place": place,
        "source": "Open-Meteo",
        "now": now,
        "next_24_hours": hours,
        "days": days,
    })
}

#[async_trait]
impl ToolExecutor for Weather {
    async fn call(&self, tool: &str, args: &Value) -> Result<ToolOutput, ToolError> {
        if tool != TOOL {
            return Err(ToolError::Unavailable(tool.to_owned()));
        }
        let asked = args
            .get("place")
            .and_then(Value::as_str)
            .map(crate::web::clean_query)
            .filter(|p| p.chars().count() >= 2);
        // Where the person lives, if they told Pilot (the newest such fact),
        // then the time zone's city.
        let home = || {
            self.store
                .as_ref()?
                .memories()
                .ok()?
                .iter()
                .rev()
                .find_map(|m| home_from_fact(&m.fact))
        };
        let place = match asked.or_else(home) {
            Some(p) => p,
            None => crate::localtime::zone_name()
                .map(|z| crate::localtime::zone_city(&z))
                .filter(|c| !c.is_empty())
                .ok_or_else(|| {
                    ToolError::Invalid("the phone's location is unknown; ask which town".into())
                })?,
        };
        let days = args
            .get("days")
            .and_then(Value::as_u64)
            .unwrap_or(3)
            .clamp(1, 10);
        // Place names in the person's language ("München", "Helsingfors"
        // in Swedish), units as they use them.
        let locale = crate::lang::current();
        let units = Units::for_locale(&locale);
        let geo = self
            .remote
            .get_json(
                "open-meteo",
                "weather place",
                &format!(
                    "{GEOCODE}?name={}&count=1&language={}&format=json",
                    enc(&place),
                    enc(locale.service_language())
                ),
            )
            .await
            .map_err(|e| ToolError::Failed(format!("weather lookup failed: {e}")))?;
        let Some(hit) = geo.body["results"].get(0) else {
            return Err(ToolError::Invalid(format!(
                "no place called \"{place}\" was found"
            )));
        };
        let (Some(lat), Some(lon)) = (num(hit, "latitude"), num(hit, "longitude")) else {
            return Err(ToolError::Failed(
                "the weather service gave no coordinates".into(),
            ));
        };
        let name = [hit["name"].as_str(), hit["country"].as_str()]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(", ");
        let url = format!(
            "{FORECAST}?latitude={lat}&longitude={lon}\
             &current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,precipitation\
             &hourly=temperature_2m,precipitation_probability,weather_code&forecast_hours=24\
             &daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code\
             &forecast_days={days}&timezone=auto{}",
            units.query()
        );
        // Once more after a moment: the service had brief outages, and "the
        // weather service is down" is a poor answer to a passing one.
        let first = self
            .remote
            .get_json("open-meteo", "weather forecast", &url)
            .await;
        let forecast = if let Ok(f) = first {
            f
        } else {
            tokio::time::sleep(std::time::Duration::from_millis(800)).await;
            self.remote
                .get_json("open-meteo", "weather forecast", &url)
                .await
                .map_err(|e| ToolError::Failed(format!("weather forecast failed: {e}")))?
        };
        let data = summarise(&name, &forecast.body, units);
        Ok(ToolOutput {
            summary: format!(
                "Weather for {name} from Open-Meteo, as of {}.",
                data["now"]["time"].as_str().unwrap_or("now")
            ),
            data,
            private: false,
            untrusted: false,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_forecast_is_summarised_for_the_model() {
        let f = json!({
            "current": {"time": "2026-10-11T12:15", "temperature_2m": 12.84, "apparent_temperature": 9.9,
                        "weather_code": 0, "wind_speed_10m": 13.0, "relative_humidity_2m": 70, "precipitation": 0.0},
            "hourly": {"time": ["t0", "t1", "t2", "t3"], "temperature_2m": [12.8, 13.0, 13.4, 13.1],
                       "precipitation_probability": [5, 10, 20, 60], "weather_code": [0, 1, 2, 61]},
            "daily": {"time": ["2026-10-11", "2026-10-12"], "temperature_2m_min": [8.6, 14.5],
                      "temperature_2m_max": [14.6, 19.9], "precipitation_probability_max": [84, 98],
                      "weather_code": [3, 51]}
        });
        let s = summarise("Dublin, Ireland", &f, Units { imperial: false });
        assert_eq!(s["now"]["temp_c"], json!(12.8));
        assert_eq!(s["now"]["sky"], "clear");
        assert_eq!(
            s["next_24_hours"].as_array().unwrap().len(),
            2,
            "every 3 hours"
        );
        assert_eq!(s["next_24_hours"][1]["sky"], "light rain");
        assert_eq!(s["days"][1]["max_c"], json!(19.9));
        assert_eq!(s["days"][1]["rain_chance_pct"], 98);
        assert_eq!(s["days"][1]["sky"], "drizzle");
        assert_eq!(s["days"][0]["day"], "Sunday");
        assert_eq!(s["days"][0]["weekend"], true);
        assert_eq!(s["days"][1]["weekend"], false);
        assert_eq!(weekday("2026-10-17"), Some("Saturday"));
        assert_eq!(weekday("2024-02-29"), Some("Thursday"));
    }

    #[test]
    fn imperial_units_are_named_as_such() {
        let f = json!({
            "current": {"time": "2026-10-11T12:15", "temperature_2m": 55.1, "apparent_temperature": 50.0,
                        "weather_code": 0, "wind_speed_10m": 8.1, "relative_humidity_2m": 70, "precipitation": 0.01},
            "hourly": {"time": ["t0"], "temperature_2m": [55.0], "precipitation_probability": [5], "weather_code": [0]},
            "daily": {"time": ["2026-10-11"], "temperature_2m_min": [47.5], "temperature_2m_max": [58.3],
                      "precipitation_probability_max": [10], "weather_code": [3]}
        });
        let us = Units::for_locale(&crate::lang::Locale::parse("en_US").unwrap());
        assert!(us.imperial);
        assert!(us.query().contains("temperature_unit=fahrenheit"));
        let s = summarise("Boston, United States", &f, us);
        assert_eq!(s["now"]["temp_f"], json!(55.1));
        assert_eq!(s["now"]["wind_mph"], json!(8.1));
        assert_eq!(s["now"]["rain_in"], json!(0.01));
        assert!(s["now"].get("temp_c").is_none());
        assert_eq!(s["next_24_hours"][0]["temp_f"], json!(55.0));
        assert_eq!(s["days"][0]["max_f"], json!(58.3));
        let ie = Units::for_locale(&crate::lang::Locale::parse("en_IE").unwrap());
        assert_eq!(ie.query(), "");
        assert_eq!(ie.key("wind"), "wind_kmh");
    }

    #[test]
    fn home_comes_from_what_was_remembered() {
        assert_eq!(
            home_from_fact("I live in Galway").as_deref(),
            Some("Galway")
        );
        assert_eq!(
            home_from_fact("we moved from Cork to Dún Laoghaire last month").as_deref(),
            Some("Dún Laoghaire")
        );
        assert_eq!(home_from_fact("my wife's name is Niamh"), None);
        assert_eq!(home_from_fact("I live in a flat"), None);
        assert_eq!(
            home_from_fact("İzmir was lovely, but I live in Galway").as_deref(),
            Some("Galway")
        );
    }

    #[test]
    fn place_names_are_encoded() {
        assert_eq!(enc("Dún Laoghaire"), "D%C3%BAn%20Laoghaire");
    }
}
