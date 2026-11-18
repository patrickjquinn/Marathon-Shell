//! The world's internet radio, from Radio Browser (radio-browser.info, an
//! open community directory): the stations with a location, cached on the
//! phone for a week and gathered into places for the globe, plus search
//! over the whole directory.

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};

const SERVERS: &[&str] = &[
    "de1.api.radio-browser.info",
    "de2.api.radio-browser.info",
    "fi1.api.radio-browser.info",
    "nl1.api.radio-browser.info",
];
const AGENT: &str = "MarathonRadio/1.0 (+https://github.com/patrickjquinn/Marathon-Shell)";
const REFRESH: Duration = Duration::from_hours(7 * 24);
/// Stations closer than this to a place's first station belong to it.
const PLACE_KM: f64 = 15.0;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub url: String,
    pub lat: f64,
    pub lon: f64,
    pub country: String,
    pub cc: String,
    pub state: String,
    pub codec: String,
    pub bitrate: u32,
    pub favicon: String,
    pub tags: String,
    pub hls: bool,
    pub popularity: u32,
    /// The station's own site, where a missing logo can be found.
    #[serde(default)]
    pub homepage: String,
}

/// Radio Browser's record, the fields used.
#[derive(Deserialize)]
struct Record {
    stationuuid: String,
    name: String,
    url_resolved: String,
    geo_lat: Option<f64>,
    geo_long: Option<f64>,
    #[serde(default)]
    country: String,
    #[serde(default)]
    countrycode: String,
    #[serde(default)]
    state: String,
    #[serde(default)]
    codec: String,
    #[serde(default)]
    bitrate: u32,
    #[serde(default)]
    favicon: String,
    #[serde(default)]
    tags: String,
    #[serde(default)]
    hls: u8,
    #[serde(default)]
    clickcount: u32,
    #[serde(default)]
    homepage: String,
}

impl Record {
    fn station(self) -> Option<Station> {
        let name = self.name.trim().to_owned();
        if name.is_empty() || self.url_resolved.is_empty() {
            return None;
        }
        Some(Station {
            id: self.stationuuid,
            name,
            url: self.url_resolved,
            lat: self.geo_lat.unwrap_or(f64::NAN),
            lon: self.geo_long.unwrap_or(f64::NAN),
            country: self.country,
            cc: self.countrycode,
            state: self.state.trim().to_owned(),
            codec: self.codec,
            bitrate: self.bitrate,
            favicon: self.favicon,
            tags: self.tags,
            hls: self.hls != 0,
            popularity: self.clickcount,
            homepage: self.homepage,
        })
    }
}

impl Station {
    pub fn located(&self) -> bool {
        self.lat.is_finite() && self.lon.is_finite()
    }
}

pub struct Place {
    pub lat: f64,
    pub lon: f64,
    pub label: String,
    /// Indices into the catalogue, most listened first.
    pub stations: Vec<usize>,
}

pub struct Catalogue {
    pub stations: Vec<Station>,
    pub places: Vec<Place>,
    by_id: HashMap<String, usize>,
    /// The most listened entry with a logo, by country and `name_key`.
    logos: HashMap<(String, String), usize>,
}

/// The everyday name of a country Radio Browser gives its ISO name ("The
/// United Kingdom Of Great Britain And Northern Ireland").
fn short_country(name: &str) -> &str {
    match name {
        "The United Kingdom Of Great Britain And Northern Ireland" => "United Kingdom",
        "The United States Of America" => "United States",
        "The Russian Federation" => "Russia",
        "Korea, Republic Of" | "The Republic Of Korea" => "South Korea",
        "Iran, Islamic Republic Of" | "Iran (Islamic Republic Of)" => "Iran",
        "Venezuela (Bolivarian Republic Of)" => "Venezuela",
        "Bolivia (Plurinational State Of)" => "Bolivia",
        "Tanzania, United Republic Of" | "The United Republic Of Tanzania" => "Tanzania",
        "Viet Nam" => "Vietnam",
        "Taiwan, Republic Of China" | "Taiwan, Province Of China" => "Taiwan",
        "The Democratic Republic Of The Congo" => "DR Congo",
        "The Netherlands" => "Netherlands",
        "The Philippines" => "Philippines",
        _ => name,
    }
}

/// A station's name for finding its other entries in the directory: its
/// words, less those about the stream ("AAC", "128k", "HQ").
pub fn name_key(name: &str) -> String {
    crate::matching::words(name)
        .into_iter()
        .filter(|w| {
            let rate = w.strip_suffix("kbps").or_else(|| w.strip_suffix('k'));
            !matches!(
                w.as_str(),
                "aac" | "mp3" | "ogg" | "opus" | "hls" | "hq" | "lq" | "stream"
            ) && !rate.is_some_and(|r| !r.is_empty() && r.chars().all(|c| c.is_ascii_digit()))
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Great-circle distance in km.
pub fn km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let (p1, p2) = (lat1.to_radians(), lat2.to_radians());
    let dp = p2 - p1;
    let dl = (lon2 - lon1).to_radians();
    let a = (dp / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dl / 2.0).sin().powi(2);
    12_742.0 * a.sqrt().min(1.0).asin()
}

fn cell(lat: f64, lon: f64) -> (i32, i32) {
    #[allow(clippy::cast_possible_truncation, reason = "degrees fit")]
    ((lat * 2.0).floor() as i32, (lon * 2.0).floor() as i32)
}

impl Catalogue {
    pub fn new(mut stations: Vec<Station>) -> Self {
        stations.sort_by_key(|s| std::cmp::Reverse(s.popularity));
        let by_id = stations
            .iter()
            .enumerate()
            .map(|(i, s)| (s.id.clone(), i))
            .collect();
        let mut places: Vec<Place> = Vec::new();
        let mut grid: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
        for (i, s) in stations.iter().enumerate().filter(|(_, s)| s.located()) {
            let (cy, cx) = cell(s.lat, s.lon);
            let near = (cy - 1..=cy + 1)
                .flat_map(|y| (cx - 1..=cx + 1).map(move |x| (y, x)))
                .filter_map(|c| grid.get(&c))
                .flatten()
                .copied()
                .find(|&p| km(places[p].lat, places[p].lon, s.lat, s.lon) < PLACE_KM);
            if let Some(p) = near {
                places[p].stations.push(i);
            } else {
                let country = short_country(&s.country);
                let label = if s.state.is_empty() || s.state == s.country {
                    country.to_owned()
                } else {
                    format!("{}, {country}", s.state)
                };
                grid.entry((cy, cx)).or_default().push(places.len());
                places.push(Place {
                    lat: s.lat,
                    lon: s.lon,
                    label,
                    stations: vec![i],
                });
            }
        }
        // Sorted by popularity, so the first logo for a name is its best known.
        let mut logos = HashMap::new();
        for (i, s) in stations.iter().enumerate() {
            if s.favicon.starts_with("http") {
                logos.entry((s.cc.clone(), name_key(&s.name))).or_insert(i);
            }
        }
        Self {
            stations,
            places,
            by_id,
            logos,
        }
    }

    pub fn get(&self, id: &str) -> Option<&Station> {
        self.by_id.get(id).map(|&i| &self.stations[i])
    }

    /// A logo for `station` when its own entry has none: another entry for
    /// the same station, in the same country.
    pub fn logo_for(&self, station: &Station) -> Option<&str> {
        let key = name_key(&station.name);
        if key.is_empty() {
            return None;
        }
        self.logos
            .get(&(station.cc.clone(), key))
            .map(|&i| self.stations[i].favicon.as_str())
    }

    /// Located stations within `radius` km of a point, nearest first.
    pub fn near(&self, lat: f64, lon: f64, radius: f64) -> Vec<&Station> {
        let mut found: Vec<(f64, &Station)> = self
            .stations
            .iter()
            .filter(|s| s.located())
            .map(|s| (km(lat, lon, s.lat, s.lon), s))
            .filter(|(d, _)| *d < radius)
            .collect();
        found.sort_by(|a, b| a.0.total_cmp(&b.0));
        found.into_iter().map(|(_, s)| s).collect()
    }

    /// Stations whose name or tags hold every word of `query`: those it
    /// names first, then those near `home`, then the most listened.
    pub fn search(&self, query: &str, limit: usize, home: Option<(f64, f64)>) -> Vec<&Station> {
        let words = crate::matching::words(query);
        if words.is_empty() {
            return Vec::new();
        }
        let holds = |hay: &[String]| {
            words
                .iter()
                .all(|w| hay.iter().any(|h| h.starts_with(w.as_str())))
        };
        let mut found: Vec<(bool, bool, usize, &Station)> = self
            .stations
            .iter()
            .enumerate()
            .filter_map(|(rank, s)| {
                let named = holds(&crate::matching::words(&s.name));
                let tagged = named
                    || holds(&crate::matching::words(&format!(
                        "{} {} {}",
                        s.name, s.tags, s.state
                    )));
                let near = home
                    .is_some_and(|(lat, lon)| s.located() && km(lat, lon, s.lat, s.lon) < 300.0);
                tagged.then_some((!named, !near, rank, s))
            })
            .collect();
        found.sort_by_key(|(n, h, rank, _)| (*n, *h, *rank));
        found
            .into_iter()
            .take(limit)
            .map(|(_, _, _, s)| s)
            .collect()
    }
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_global(Some(Duration::from_secs(90)))
        .user_agent(AGENT)
        .build()
        .new_agent()
}

/// `path` from the first Radio Browser server that answers.
fn get(path: &str, limit: u64) -> Result<Vec<u8>, String> {
    let agent = agent();
    let mut last = String::new();
    for server in SERVERS {
        match agent.get(&format!("https://{server}{path}")).call() {
            Ok(resp) => {
                return resp
                    .into_body()
                    .with_config()
                    .limit(limit)
                    .read_to_vec()
                    .map_err(|e| e.to_string())
            }
            Err(e) => last = format!("{server}: {e}"),
        }
    }
    Err(last)
}

fn records(body: &[u8]) -> Result<Vec<Station>, String> {
    let records: Vec<Record> = serde_json::from_slice(body).map_err(|e| e.to_string())?;
    Ok(records.into_iter().filter_map(Record::station).collect())
}

fn cache() -> PathBuf {
    // v2: stations carry their homepage.
    marathon_rt::dirs::cache().join("marathon/radio/stations-v2.json")
}

/// The cached catalogue, and whether it is due a refresh.
pub fn cached() -> Option<(Vec<Station>, bool)> {
    let path = cache();
    let age = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| SystemTime::now().duration_since(t).ok())?;
    let stations = serde_json::from_slice(&std::fs::read(&path).ok()?).ok()?;
    Some((stations, age > REFRESH))
}

/// Every station with a location, fetched and cached.
pub fn fetch() -> Result<Vec<Station>, String> {
    // The cache from before stations had homepages.
    std::fs::remove_file(marathon_rt::dirs::cache().join("marathon/radio/stations.json")).ok();
    let body = get(
        "/json/stations/search?has_geo_info=true&hidebroken=true&order=clickcount&reverse=true&limit=100000",
        64 << 20,
    )?;
    let stations = records(&body)?;
    let path = cache();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    if let Ok(json) = serde_json::to_vec(&stations) {
        let tmp = path.with_extension("part");
        if std::fs::write(&tmp, json).is_ok() {
            std::fs::rename(tmp, &path).ok();
        }
    }
    Ok(stations)
}

/// The directory's station `id` (a UUID), for one a list named before this
/// daemon started.
pub fn by_id(id: &str) -> Option<Station> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        return None;
    }
    let body = get(&format!("/json/stations/byuuid/{id}"), 1 << 20).ok()?;
    records(&body).ok()?.into_iter().next()
}

/// The whole directory's stations named like `query`, located or not.
pub fn search_online(query: &str, limit: usize) -> Result<Vec<Station>, String> {
    let q: String = query
        .bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect();
    let body = get(
        &format!("/json/stations/search?name={q}&hidebroken=true&order=clickcount&reverse=true&limit={limit}"),
        8 << 20,
    )?;
    records(&body)
}

/// The station's stream, counted as a listen as Radio Browser asks.
pub fn resolve(station: &Station) -> String {
    #[derive(Deserialize)]
    struct Click {
        ok: bool,
        url: String,
    }
    get(&format!("/json/url/{}", station.id), 1 << 16)
        .ok()
        .and_then(|b| serde_json::from_slice::<Click>(&b).ok())
        .filter(|c| c.ok && !c.url.is_empty())
        .map_or_else(|| station.url.clone(), |c| c.url)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn station(id: &str, lat: f64, lon: f64, popularity: u32) -> Station {
        Station {
            id: id.into(),
            name: id.into(),
            url: "http://x".into(),
            lat,
            lon,
            country: "Ireland".into(),
            cc: "IE".into(),
            state: "Dublin".into(),
            codec: "MP3".into(),
            bitrate: 128,
            favicon: String::new(),
            tags: "pop,news".into(),
            hls: false,
            popularity,
            homepage: String::new(),
        }
    }

    #[test]
    fn a_station_without_a_logo_borrows_its_other_entry_s() {
        let mut bare = station("RTÉ lyric fm", 53.3, -6.2, 50);
        let mut aac = station("RTE Lyric FM (AAC 128k)", 53.3, -6.2, 10);
        aac.favicon = "https://www.rte.ie/lyric.png".into();
        let mut elsewhere = station("Lyric FM", 51.5, -0.1, 99);
        elsewhere.cc = "GB".into();
        elsewhere.favicon = "https://example.uk/lyric.png".into();
        let c = Catalogue::new(vec![bare.clone(), aac, elsewhere]);
        assert_eq!(c.logo_for(&bare), Some("https://www.rte.ie/lyric.png"));
        bare.name = "Radio Kerry".into();
        assert_eq!(c.logo_for(&bare), None);
    }

    #[test]
    fn nearby_stations_share_a_place_led_by_the_most_listened() {
        let c = Catalogue::new(vec![
            station("quiet", 53.30, -6.20, 1),
            station("loud", 53.35, -6.26, 100),
            station("cork", 51.90, -8.47, 50),
        ]);
        assert_eq!(c.places.len(), 2);
        let dublin = &c.places[0];
        assert_eq!(dublin.label, "Dublin, Ireland");
        let names: Vec<&str> = dublin
            .stations
            .iter()
            .map(|&i| c.stations[i].name.as_str())
            .collect();
        assert_eq!(names, ["loud", "quiet"]);
    }

    #[test]
    fn search_matches_word_starts_in_name_and_tags() {
        let c = Catalogue::new(vec![station("Radio Nova", 53.3, -6.2, 5)]);
        assert_eq!(c.search("nov", 5, None).len(), 1);
        assert_eq!(c.search("news", 5, None).len(), 1);
        assert_eq!(c.search("jazz", 5, None).len(), 0);
    }

    #[test]
    fn search_puts_named_and_nearby_stations_first() {
        let mut far = station("Nova Germany", 52.5, 13.4, 1000);
        far.name = "Deutschlandfunk Nova".into();
        let mut tagged = station("Jazz", 53.3, -6.2, 900);
        tagged.tags = "nova".into();
        let mut home = station("Nova Dublin", 53.35, -6.26, 10);
        home.name = "Radio Nova".into();
        let c = Catalogue::new(vec![far, tagged, home]);
        let names: Vec<&str> = c
            .search("nova", 5, Some((53.33, -6.25)))
            .iter()
            .map(|s| s.name.as_str())
            .collect();
        assert_eq!(names, ["Radio Nova", "Deutschlandfunk Nova", "Jazz"]);
    }

    #[test]
    fn distances_are_great_circle() {
        assert!((km(53.35, -6.26, 51.90, -8.47) - 219.0).abs() < 5.0);
    }
}
