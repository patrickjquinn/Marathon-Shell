// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `weather.forecast`: the weather now and day by day from Marathon's
//! weather service (marathon-weatherd, MET Norway), the one the Weather
//! app shows: for where the phone is when no place is named, else for the
//! place the service's search finds. Web pages are no source for weather:
//! their snippets are hours old, and Pilot told the person it was 6 °C and
//! overcast in Dublin when it was 12.8 °C and clear.

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::{json, Value};

use crate::schema::Validator;
use crate::tools::{Confirm, Registry, ToolError, ToolExecutor, ToolOutput, ToolSpec};

pub const TOOL: &str = "weather.forecast";
const BUS: &str = "org.marathonos.Weather";
const PATH: &str = "/org/marathonos/Weather";
const INTERFACE: &str = "org.marathonos.Weather1";

pub struct Weather;

/// The tool's declaration.
///
/// # Panics
///
/// Never: the schema is static and valid.
#[allow(clippy::expect_used, reason = "compiled-in schemas")]
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
pub fn register(registry: &mut Registry) {
    registry.add(spec(), true, Arc::new(Weather));
}

/// A MET Norway symbol in words: `lightrainshowers_day` -> "light rain
/// showers".
pub fn sky(symbol: &str) -> String {
    const WORDS: [&str; 14] = [
        "partly", "cloudy", "clear", "sky", "fair", "fog", "light", "heavy", "rain", "showers",
        "sleet", "snow", "and", "thunder",
    ];
    let mut rest = symbol.split('_').next().unwrap_or(symbol);
    let mut words = Vec::new();
    while !rest.is_empty() {
        let Some(word) = WORDS.iter().find(|w| rest.starts_with(**w)) else {
            words.push(rest);
            break;
        };
        words.push(word);
        rest = &rest[word.len()..];
    }
    match words.join(" ").as_str() {
        "clear sky" => "clear".into(),
        other => other.into(),
    }
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

/// The units a forecast is given in: metric, or (the United States,
/// Liberia and Myanmar) Fahrenheit, mph and inches.
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

    fn temp(self, celsius: f64) -> f64 {
        if self.imperial {
            celsius * 1.8 + 32.0
        } else {
            celsius
        }
    }

    /// From the service's metres per second.
    fn wind(self, metres_per_second: f64) -> f64 {
        metres_per_second * if self.imperial { 2.236_94 } else { 3.6 }
    }

    fn rain(self, millimetres: f64) -> f64 {
        if self.imperial {
            millimetres / 25.4
        } else {
            millimetres
        }
    }

    fn degree(self) -> &'static str {
        if self.imperial {
            "°F"
        } else {
            "°C"
        }
    }
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

#[allow(clippy::cast_possible_truncation, reason = "a temperature")]
fn whole(x: f64) -> i64 {
    x.round() as i64
}

/// "13:00" in the place's own time.
fn clock(epoch: i64, offset: i64) -> String {
    let seconds = (epoch + offset).rem_euclid(86_400);
    format!("{:02}:{:02}", seconds / 3600, seconds % 3600 / 60)
}

const WEEK: usize = 7;

/// The model's view of the service's forecast (`f`, as `Forecast` gives it)
/// and the forecast in words, for the first `days` days. The model sees a
/// week at least: it counted four days to "this weekend" from a Wednesday.
pub fn summarise(place: &str, f: &Value, units: Units, days: usize) -> (Value, String) {
    let k = |name: &str| units.key(name);
    let offset = f["timezone_offset"].as_i64().unwrap_or_default();
    let cur = &f["current"];
    let mut now = json!({
        "time": cur["time"].as_i64().map(|t| clock(t, offset)),
        "sky": cur["symbol"].as_str().map(sky),
        "humidity_pct": cur.get("humidity"),
    });
    now[k("temp")] = json!(num(cur, "temperature").map(|t| round1(units.temp(t))));
    now[k("feels_like")] = json!(num(cur, "apparent").map(|t| round1(units.temp(t))));
    now[k("wind")] = json!(num(cur, "wind_speed").map(|w| round1(units.wind(w))));
    let hours: Vec<Value> = f["hourly"]
        .as_array()
        .map(|h| {
            h.iter()
                .step_by(3)
                .take(8)
                .map(|h| {
                    let mut out = json!({
                        "time": h["time"].as_i64().map(|t| clock(t, offset)),
                        "sky": h["symbol"].as_str().map(sky),
                        "rain_chance_pct": h.get("precipitation_probability"),
                    });
                    out[k("temp")] = json!(num(h, "temperature").map(|t| round1(units.temp(t))));
                    out
                })
                .collect()
        })
        .unwrap_or_default();
    let daily: Vec<&Value> = f["daily"]
        .as_array()
        .map(|d| d.iter().take(days.max(WEEK)).collect())
        .unwrap_or_default();
    let day_rows: Vec<Value> = daily
        .iter()
        .map(|d| {
            let date = d["date"].as_str().unwrap_or("");
            let mut out = json!({
                "date": date,
                "day": weekday(date),
                "sky": d["symbol"].as_str().map(sky),
                "rain_chance_pct": d.get("precipitation_probability"),
            });
            out[k("min")] = json!(num(d, "low").map(|t| round1(units.temp(t))));
            out[k("max")] = json!(num(d, "high").map(|t| round1(units.temp(t))));
            out[k("rain")] = json!(num(d, "precipitation").map(|r| round1(units.rain(r))));
            out
        })
        .collect();
    let data = json!({
        "place": place,
        "source": "MET Norway",
        "now": now,
        "next_24_hours": hours,
        "days": day_rows,
    });
    (data, answer(place, f, units, days))
}

/// The forecast in words: now, then each of the first `days` days.
fn answer(place: &str, f: &Value, units: Units, days: usize) -> String {
    let degree = units.degree();
    let cur = &f["current"];
    let mut sentences = Vec::new();
    if let Some(t) = num(cur, "temperature") {
        let mut now = vec![format!("{place}: {}{degree}", whole(units.temp(t)))];
        if let Some(s) = cur["symbol"].as_str() {
            now.push(format!("and {}", sky(s)));
        }
        now.push("now".into());
        let mut sentence = now.join(" ");
        if let Some(a) = num(cur, "apparent").filter(|a| (a - t).abs() >= 2.0) {
            sentence = format!("{sentence}, feels like {}{degree}", whole(units.temp(a)));
        }
        sentences.push(format!("{sentence}."));
    }
    let daily = f["daily"].as_array().map_or(&[][..], Vec::as_slice);
    for (i, d) in daily.iter().take(days).enumerate() {
        let (Some(low), Some(high)) = (num(d, "low"), num(d, "high")) else {
            continue;
        };
        let label = match i {
            0 => "Today",
            1 => "Tomorrow",
            _ => d["date"].as_str().and_then(weekday).unwrap_or(""),
        };
        let mut parts = vec![match d["symbol"].as_str() {
            Some(s) => format!("{label} {}", sky(s)),
            None => label.to_owned(),
        }];
        parts.push(format!(
            "{} to {}{degree}",
            whole(units.temp(low)),
            whole(units.temp(high))
        ));
        let rain = num(d, "precipitation").unwrap_or_default();
        parts.push(match d["precipitation_probability"].as_i64() {
            Some(p) if p >= 20 => format!("{p}% chance of rain"),
            _ if rain >= 0.2 => format!(
                "{} {} of rain",
                round1(units.rain(rain)),
                if units.imperial { "in" } else { "mm" }
            ),
            _ => "dry".into(),
        });
        sentences.push(format!("{}.", parts.join(", ")));
    }
    sentences.join(" ")
}

async fn service() -> Result<zbus::Proxy<'static>, ToolError> {
    let unavailable = |e: zbus::Error| ToolError::Unavailable(format!("the weather service: {e}"));
    let bus = zbus::Connection::session().await.map_err(unavailable)?;
    zbus::Proxy::new(&bus, BUS, PATH, INTERFACE)
        .await
        .map_err(unavailable)
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
        let days = args
            .get("days")
            .and_then(Value::as_u64)
            .unwrap_or(3)
            .clamp(1, 10);
        let units = Units::for_locale(&crate::lang::current());
        let weather = service().await?;
        let failed = |e: zbus::Error| ToolError::Failed(format!("the weather service: {e}"));
        let (place, forecast) = match asked {
            None => {
                let text: String = weather.get_property("Forecast").await.map_err(failed)?;
                let forecast: Value = serde_json::from_str(&text).map_err(|_empty| {
                    ToolError::Invalid("the phone's location is unknown; ask which town".into())
                })?;
                let name = forecast["location"]["name"]
                    .as_str()
                    .unwrap_or("Here")
                    .to_owned();
                (name, forecast)
            }
            Some(place) => {
                let found: String = weather
                    .call("Search", &(place.as_str(),))
                    .await
                    .map_err(failed)?;
                let found: Value = serde_json::from_str(&found).unwrap_or_default();
                let Some(hit) = found.get(0) else {
                    return Err(ToolError::Invalid(format!(
                        "no place called \"{place}\" was found"
                    )));
                };
                let (Some(lat), Some(lon)) = (num(hit, "latitude"), num(hit, "longitude")) else {
                    return Err(ToolError::Failed("the place has no coordinates".into()));
                };
                let text: String = weather
                    .call("ForecastAt", &(lat, lon))
                    .await
                    .map_err(failed)?;
                let forecast = serde_json::from_str(&text)
                    .map_err(|e| ToolError::BadOutput(format!("the weather service: {e}")))?;
                (hit["name"].as_str().unwrap_or(&place).to_owned(), forecast)
            }
        };
        let (data, summary) =
            summarise(&place, &forecast, units, usize::try_from(days).unwrap_or(3));
        Ok(ToolOutput {
            summary,
            data,
            private: false,
            untrusted: false,
            answers: true,
        })
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn a_forecast_is_answered_in_words() {
        let f = json!({
            "timezone_offset": 0,
            "current": {"time": 1_793_188_800, "temperature": 14.0, "apparent": 10.4,
                        "symbol": "partlycloudy", "humidity": 73, "wind_speed": 4.9},
            "hourly": [{"time": 1_793_192_400, "temperature": 14.6, "symbol": "lightrainshowers_day",
                        "precipitation_probability": 40}],
            "daily": [{"date": "2026-10-28", "high": 14.7, "low": 10.5, "precipitation": 0.0,
                       "precipitation_probability": null, "symbol": "partlycloudy"},
                      {"date": "2026-10-29", "high": 13.4, "low": 10.6, "precipitation": 2.4,
                       "precipitation_probability": null, "symbol": "rainshowers_day"},
                      {"date": "2026-10-31", "high": 14.2, "low": 7.9, "precipitation": 0.0,
                       "precipitation_probability": 60, "symbol": "cloudy"}]
        });
        let (data, words) = summarise("Dublin", &f, Units { imperial: false }, 3);
        assert_eq!(
            words,
            "Dublin: 14°C and partly cloudy now, feels like 10°C. Today partly cloudy, 11 to 15°C, \
             dry. Tomorrow rain showers, 11 to 13°C, 2.4 mm of rain. Saturday cloudy, 8 to 14°C, \
             60% chance of rain."
        );
        assert_eq!(data["now"]["wind_kmh"], json!(17.6));
        assert_eq!(data["next_24_hours"][0]["sky"], "light rain showers");
        assert_eq!(data["days"][2]["day"], "Saturday");
        let (us, words) = summarise("Boston", &f, Units { imperial: true }, 1);
        assert!(words.starts_with("Boston: 57°F"));
        assert_eq!(us["now"]["wind_mph"], json!(11.0));
        assert_eq!(weekday("2024-02-29"), Some("Thursday"));
    }
}
