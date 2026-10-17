//! Place names from OpenStreetMap Nominatim. Its usage policy allows at most
//! one request a second and asks for results to be cached; search runs only
//! on an explicit submit from the shell.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

const BASE: &str = "https://nominatim.openstreetmap.org";
const MIN_INTERVAL: Duration = Duration::from_secs(1);

#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub name: String,
    pub region: String,
    pub latitude: f64,
    pub longitude: f64,
}

impl Place {
    pub fn to_json(&self) -> Value {
        json!({
            "name": self.name,
            "region": self.region,
            "latitude": round4(self.latitude),
            "longitude": round4(self.longitude),
        })
    }
}

fn round4(x: f64) -> f64 {
    (x * 10_000.0).round() / 10_000.0
}

fn coord(v: &Value, key: &str) -> Option<f64> {
    match &v[key] {
        Value::String(s) => s.parse().ok(),
        other => other.as_f64(),
    }
}

/// One jsonv2 result (search or reverse, with address details).
pub fn parse_place(v: &Value) -> Option<Place> {
    let address = &v["address"];
    let field = |key: &str| address[key].as_str().filter(|s| !s.is_empty());
    let name = v["name"]
        .as_str()
        .filter(|s| !s.is_empty())
        .or_else(|| {
            [
                "city",
                "town",
                "village",
                "municipality",
                "hamlet",
                "suburb",
            ]
            .into_iter()
            .find_map(field)
        })?
        .to_owned();
    let mut region: Vec<&str> = Vec::new();
    for part in [field("state").or_else(|| field("county")), field("country")]
        .into_iter()
        .flatten()
    {
        if part != name && !region.contains(&part) {
            region.push(part);
        }
    }
    Some(Place {
        region: region.join(", "),
        name,
        latitude: coord(v, "lat")?,
        longitude: coord(v, "lon")?,
    })
}

/// Results that read the same (a city and its municipality) keep the first.
pub fn parse_search(v: &Value) -> Vec<Place> {
    let mut places: Vec<Place> = Vec::new();
    for place in v.as_array().into_iter().flatten().filter_map(parse_place) {
        if !places
            .iter()
            .any(|p| p.name == place.name && p.region == place.region)
        {
            places.push(place);
        }
    }
    places
}

/// `en_IE.UTF-8` → `en-IE`, so names come back in the user's language.
pub fn accept_language(locale: &str) -> String {
    let tag = locale
        .split(['.', '@', ':'])
        .next()
        .unwrap_or_default()
        .replace('_', "-");
    if tag.is_empty() || tag == "C" || tag == "POSIX" {
        "en".into()
    } else {
        tag
    }
}

pub struct Nominatim {
    agent: ureq::Agent,
    language: String,
    last_request: Mutex<Option<Instant>>,
    searches: Mutex<HashMap<String, Vec<Place>>>,
}

impl Nominatim {
    pub fn new(agent: ureq::Agent) -> Self {
        let locale = ["LC_ALL", "LC_MESSAGES", "LANG"]
            .into_iter()
            .find_map(|var| std::env::var(var).ok().filter(|v| !v.is_empty()))
            .unwrap_or_default();
        Nominatim {
            agent,
            language: accept_language(&locale),
            last_request: Mutex::new(None),
            searches: Mutex::new(HashMap::new()),
        }
    }

    /// Holds the rate-limit lock for the whole request, so concurrent
    /// callers queue a second apart.
    fn get(&self, path: &str, query: &[(&str, &str)]) -> Result<Value, String> {
        let mut last = self
            .last_request
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(wait) = last.and_then(|t| MIN_INTERVAL.checked_sub(t.elapsed())) {
            std::thread::sleep(wait);
        }
        *last = Some(Instant::now());
        let mut request = self
            .agent
            .get(format!("{BASE}/{path}"))
            .header("Accept-Language", &self.language)
            .config()
            .timeout_global(Some(Duration::from_secs(10)))
            .build();
        for (key, value) in query {
            request = request.query(*key, *value);
        }
        let body = request
            .call()
            .and_then(|mut r| r.body_mut().read_to_string())
            .map_err(|e| e.to_string())?;
        serde_json::from_str(&body).map_err(|e| e.to_string())
    }

    pub fn search(&self, query: &str) -> Result<Vec<Place>, String> {
        let key = query.trim().to_lowercase();
        if key.is_empty() {
            return Ok(Vec::new());
        }
        if let Some(hit) = self.cached_search(&key) {
            return Ok(hit);
        }
        let places = parse_search(&self.get(
            "search",
            &[
                ("format", "jsonv2"),
                ("q", query.trim()),
                ("limit", "8"),
                ("addressdetails", "1"),
            ],
        )?);
        self.searches
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(key, places.clone());
        Ok(places)
    }

    fn cached_search(&self, key: &str) -> Option<Vec<Place>> {
        self.searches
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(key)
            .cloned()
    }

    pub fn reverse(&self, latitude: f64, longitude: f64) -> Result<Place, String> {
        let (lat, lon) = (format!("{latitude:.4}"), format!("{longitude:.4}"));
        let v = self.get(
            "reverse",
            &[
                ("format", "jsonv2"),
                ("lat", &lat),
                ("lon", &lon),
                ("zoom", "10"),
                ("addressdetails", "1"),
            ],
        )?;
        parse_place(&v).ok_or_else(|| "no place at this point".to_owned())
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn fixture(name: &str) -> Value {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn parses_a_search() {
        let places = parse_search(&fixture("nominatim-search-tampere.json"));
        assert_eq!(
            places,
            [Place {
                name: "Tampere".into(),
                region: "Pirkanmaa, Suomi / Finland".into(),
                latitude: 61.497_798_8,
                longitude: 23.761_633_5,
            }]
        );
        assert_eq!(
            places[0].to_json(),
            json!({"name": "Tampere", "region": "Pirkanmaa, Suomi / Finland",
                   "latitude": 61.4978, "longitude": 23.7616})
        );
    }

    #[test]
    fn keeps_one_of_places_that_read_the_same() {
        let city = json!({"lat": "59.91", "lon": "10.74", "name": "Oslo",
            "address": {"country": "Norway", "country_code": "no"}});
        let municipality = json!({"lat": "59.95", "lon": "10.75", "name": "Oslo",
            "address": {"country": "Norway", "country_code": "no"}});
        let places = parse_search(&json!([city, municipality]));
        assert_eq!(places.len(), 1);
        assert!((places[0].latitude - 59.91).abs() < 1e-9);
    }

    #[test]
    fn parses_a_reverse_lookup_without_a_state() {
        let place = parse_place(&fixture("nominatim-reverse-dublin.json")).unwrap();
        assert_eq!(place.name, "Dublin");
        assert_eq!(place.region, "County Dublin, Éire / Ireland");
    }

    #[test]
    fn falls_back_to_the_address_for_a_nameless_result() {
        let place = parse_place(&json!({
            "lat": "1.5", "lon": "2.5", "name": "",
            "address": {"town": "Kilkee", "county": "County Clare", "country": "Ireland"}
        }))
        .unwrap();
        assert_eq!(place.name, "Kilkee");
        assert_eq!(place.region, "County Clare, Ireland");
        assert!(parse_place(&json!({"lat": "1", "lon": "2", "address": {}})).is_none());
        assert!(parse_search(&json!({"error": "x"})).is_empty());
    }

    #[test]
    fn accept_language_from_locale() {
        assert_eq!(accept_language("en_IE.UTF-8"), "en-IE");
        assert_eq!(accept_language("fi_FI@euro"), "fi-FI");
        assert_eq!(accept_language("C.UTF-8"), "en");
        assert_eq!(accept_language(""), "en");
    }
}
