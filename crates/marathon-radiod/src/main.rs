//! Marathon's radio: `org.marathonos.Radio` on the session bus.
//!
//! Two sources, one player: the phone's FM tuner (the wired headset is its
//! aerial) and the world's internet stations from Radio Browser. A local
//! station that is on FM plays over FM while the headset is in. Either
//! plays through `PipeWire` as Music, and while it does radiod is an MPRIS
//! player, so the lock screen and media controls show the station and what
//! it is playing (RDS radio text on FM, the stream's own title online). A
//! phone call stops it.

mod catalogue;
mod fm;
mod home;
mod icy;
mod library;
mod matching;
mod mpris;
mod route;
mod stream;

use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use async_io::Timer;
use futures_lite::{future, StreamExt};
use marathon_rt::daemon::Shared;
use marathon_rt::{io, log};
use serde::{Deserialize, Serialize};
use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface, Connection, MatchRule, MessageStream, ObjectPath};
use zbus::{OwnedVariant as OwnedValue, Variant};

use catalogue::{Catalogue, Station};
use fm::{Fm, Rds};
use library::Library;
use mpris::{Player, Root};
use route::Route;
use stream::{Event, Stream, Tx};

const BUS_NAME: &str = "org.marathonos.Radio";
const PATH: &str = "/org/marathonos/Radio";
const MPRIS_NAME: &str = "org.mpris.MediaPlayer2.radio";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const ICON: &str = "file:///usr/share/marathon-apps/radio/assets/icon.svg";
/// 98.0 MHz, where FM starts before any station is known.
const FIRST: u16 = 9800;
/// How far from home an internet station may be and still be on local FM.
const LOCAL_KM: f64 = 150.0;
const FM_PREFIX: &str = "fm:";

type Dict = HashMap<String, OwnedValue>;

fn put(map: &mut Dict, key: &str, value: Variant<'_>) {
    if let Ok(v) = OwnedValue::try_from(value) {
        map.insert(key.to_owned(), v);
    }
}

/// The frequency (10 kHz) in an FM station's id, which is in kHz.
fn fm_id(khz: &str) -> Option<u16> {
    khz.parse::<u32>()
        .ok()
        .and_then(|k| u16::try_from(k / 10).ok())
        .filter(|f| (fm::LOWEST..=fm::HIGHEST).contains(f))
}

/// "100.3 FM".
fn mhz(freq: u16) -> String {
    format!("{}.{} FM", freq / 100, freq % 100 / 10)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Status {
    Stopped,
    Connecting,
    Playing,
    Failed,
}

impl Status {
    fn name(self) -> &'static str {
        match self {
            Self::Stopped => "stopped",
            Self::Connecting => "connecting",
            Self::Playing => "playing",
            Self::Failed => "failed",
        }
    }

    fn sounding(self) -> bool {
        matches!(self, Self::Connecting | Self::Playing)
    }
}

enum Source {
    Fm {
        fm: Fm,
        route: Route,
    },
    /// Held for its life: dropping it stops the stream.
    Online(#[allow(dead_code, reason = "dropping it stops the stream")] Stream),
}

/// The FM band as last scanned, and the RDS name each station sent.
#[derive(Default, Serialize, Deserialize)]
struct Band {
    stations: Vec<u16>,
    names: BTreeMap<u16, (u16, String)>,
}

fn band_path() -> std::path::PathBuf {
    marathon_rt::dirs::cache().join("marathon/radio/fm.json")
}

impl Band {
    fn load() -> Self {
        std::fs::read(band_path())
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default()
    }

    fn save(&self) {
        let path = band_path();
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).ok();
        }
        if let Ok(json) = serde_json::to_vec(self) {
            std::fs::write(path, json).ok();
        }
    }
}

struct Radio {
    source: Option<Source>,
    status: Status,
    error: String,
    station: Option<Station>,
    /// On FM: the frequency playing; the tuner's last one otherwise.
    frequency: u16,
    title: String,
    artist: String,
    rds: Option<Rds>,
    band: Band,
    scanning: bool,
    /// The tuner powered for a survey of the band's RDS names.
    survey: Option<Fm>,
    catalogue: Option<Arc<Catalogue>>,
    catalogue_state: &'static str,
    library: Library,
    home: Option<(f64, f64)>,
    /// The phone's country (ISO 3166 alpha-2), from its time zone.
    country: String,
    /// Stations handed out lately (search results are not in the catalogue).
    seen: HashMap<String, Station>,
    /// The list the station was played from: Next and Previous go through it.
    context: Vec<String>,
    generation: u64,
    events: async_channel::Sender<(u64, Event)>,
}

impl Radio {
    fn tuner(&self) -> Option<&Fm> {
        match &self.source {
            Some(Source::Fm { fm, .. }) => Some(fm),
            _ => None,
        }
    }

    fn remember(&mut self, s: &Station) {
        if self.seen.len() > 2000 {
            self.seen.clear();
        }
        self.seen.insert(s.id.clone(), s.clone());
    }

    fn find(&self, id: &str) -> Option<Station> {
        self.catalogue
            .as_ref()
            .and_then(|c| c.get(id).cloned())
            .or_else(|| self.seen.get(id).cloned())
            .or_else(|| {
                let lib = &self.library;
                lib.favourites
                    .iter()
                    .chain(&lib.recents)
                    .find(|s| s.id == id)
                    .cloned()
            })
    }

    /// The FM frequency `station` is on here, if it is a local one.
    fn fm_for(&self, station: &Station) -> Option<u16> {
        if let Some(khz) = station.id.strip_prefix(FM_PREFIX) {
            return fm_id(khz);
        }
        // Local: near home, or, with no location in the directory, from the
        // phone's country ("Radio Nova 100" has none).
        let local = if station.located() {
            let (lat, lon) = self.home?;
            catalogue::km(lat, lon, station.lat, station.lon) <= LOCAL_KM
        } else {
            !self.country.is_empty() && station.cc.eq_ignore_ascii_case(&self.country)
        };
        if !local {
            return None;
        }
        let on_band = |f: u16| self.band.stations.contains(&f);
        matching::frequency_in(&station.name)
            .filter(|&f| on_band(f))
            .or_else(|| {
                self.band
                    .names
                    .iter()
                    .find(|(f, (_, ps))| on_band(**f) && matching::rds_names(ps, &station.name))
                    .map(|(f, _)| *f)
            })
    }

    /// The internet station that is FM station `freq`, if any.
    fn online_for(&self, freq: u16) -> Option<Station> {
        let near = match (self.home, self.catalogue.as_ref()) {
            (Some((lat, lon)), Some(c)) => c.near(lat, lon, LOCAL_KM),
            _ => Vec::new(),
        };
        // Then those without a location the person has come across
        // (searched, kept, played): "Radio Nova 100" for NOVA.
        let lib = &self.library;
        near.into_iter()
            .chain(self.seen.values())
            .chain(lib.favourites.iter().chain(&lib.recents))
            .find(|s| !s.id.starts_with(FM_PREFIX) && self.fm_for(s) == Some(freq))
            .cloned()
    }

    /// FM station `freq` as a station: the internet one it matches, under
    /// an FM id, else its RDS name.
    fn fm_station(&self, freq: u16) -> Station {
        let ps = self.band.names.get(&freq).map(|(_, ps)| ps.clone());
        let (lat, lon) = self.home.unwrap_or((f64::NAN, f64::NAN));
        let mut s = self.online_for(freq).unwrap_or_else(|| Station {
            id: String::new(),
            name: ps
                .filter(|p| !p.is_empty())
                .map_or_else(|| mhz(freq), |p| matching::title_case(&p)),
            url: String::new(),
            lat,
            lon,
            country: String::new(),
            cc: String::new(),
            state: String::new(),
            codec: String::new(),
            bitrate: 0,
            favicon: String::new(),
            tags: String::new(),
            hls: false,
            popularity: 0,
        });
        s.id = format!("{FM_PREFIX}{}", u32::from(freq) * 10);
        s.codec = "FM".into();
        s
    }

    fn dict(&self, s: &Station) -> Dict {
        let mut d = Dict::new();
        let fm = self.fm_for(s);
        put(&mut d, "id", s.id.as_str().into());
        put(&mut d, "name", s.name.as_str().into());
        let logo = if s.favicon.starts_with("http") {
            Some(s.favicon.as_str())
        } else {
            self.catalogue.as_ref().and_then(|c| c.logo_for(s))
        };
        put(&mut d, "favicon", logo.unwrap_or("").into());
        put(&mut d, "country", s.country.as_str().into());
        put(&mut d, "region", s.state.as_str().into());
        put(&mut d, "codec", s.codec.as_str().into());
        put(&mut d, "bitrate", s.bitrate.into());
        let tags: Vec<&str> = s
            .tags
            .split(',')
            .map(str::trim)
            .filter(|t| !t.is_empty())
            .take(3)
            .collect();
        put(&mut d, "tags", tags.join(" · ").as_str().into());
        put(&mut d, "fm", fm.map_or(0, |f| i32::from(f) * 10).into());
        // What the station sends over RDS, as the band survey heard it.
        let rds = fm
            .and_then(|f| self.band.names.get(&f))
            .map_or("", |(_, ps)| ps.trim());
        put(&mut d, "rds", rds.into());
        put(&mut d, "favourite", self.library.is_favourite(&s.id).into());
        if s.located() {
            put(&mut d, "lat", s.lat.into());
            put(&mut d, "lon", s.lon.into());
        }
        d
    }

    /// Stations for the app, local FM first.
    fn list(&mut self, stations: Vec<Station>) -> Vec<Dict> {
        // One entry per FM station: a station's several streams (AAC, MP3)
        // all match its frequency.
        let mut on_air = Vec::new();
        let mut with_fm: Vec<(bool, Station)> = Vec::new();
        for s in stations {
            match self.fm_for(&s) {
                Some(f) if on_air.contains(&f) => {}
                Some(f) => {
                    on_air.push(f);
                    with_fm.push((true, s));
                }
                None => with_fm.push((false, s)),
            }
        }
        with_fm.sort_by_key(|(fm, _)| !*fm);
        with_fm
            .into_iter()
            .map(|(_, s)| {
                self.remember(&s);
                self.dict(&s)
            })
            .collect()
    }

    fn state(&self) -> Dict {
        let mut s = Dict::new();
        put(&mut s, "available", Path::new("/dev/fm").exists().into());
        put(&mut s, "headset", route::headset().into());
        put(&mut s, "status", self.status.name().into());
        put(&mut s, "playing", self.status.sounding().into());
        put(&mut s, "error", self.error.as_str().into());
        put(&mut s, "onFm", self.tuner().is_some().into());
        put(&mut s, "frequency", (i32::from(self.frequency) * 10).into());
        put(&mut s, "title", self.title.as_str().into());
        put(&mut s, "artist", self.artist.as_str().into());
        put(&mut s, "scanning", self.scanning.into());
        put(&mut s, "catalogue", self.catalogue_state.into());
        if let Some(st) = &self.station {
            put(&mut s, "station", Variant::from(self.dict(st)));
        }
        if let Some((lat, lon)) = self.home {
            put(&mut s, "home", vec![lat, lon].into());
        }
        if let Some(t) = self.tuner() {
            put(&mut s, "signal", t.rssi().unwrap_or(0).into());
            put(&mut s, "stereo", t.stereo().unwrap_or(false).into());
        }
        s
    }

    fn stop(&mut self) {
        self.generation += 1;
        if let Some(Source::Fm { fm, route }) = self.source.take() {
            drop(route);
            fm.power_down().ok();
        }
        self.status = Status::Stopped;
        self.title.clear();
        self.artist.clear();
        self.rds = None;
    }

    fn begin(&mut self, station: &Station) {
        self.stop();
        if let Some(fm) = self.survey.take() {
            fm.power_down().ok();
        }
        self.error.clear();
        self.station = Some(station.clone());
        self.library.played(station);
    }

    fn play_fm(&mut self, freq: u16, station: Station) -> std::io::Result<()> {
        if let Some(fm) = self.tuner() {
            self.frequency = fm.tune(freq)?;
            self.library.played(&station);
            self.station = Some(station);
            self.title.clear();
            self.artist.clear();
            self.rds = None;
            return Ok(());
        }
        self.begin(&station);
        let fm = Fm::open()?;
        self.frequency = fm.power_up(freq)?;
        match Route::start() {
            Ok(route) => {
                self.source = Some(Source::Fm { fm, route });
                self.status = Status::Playing;
                Ok(())
            }
            Err(e) => {
                fm.power_down().ok();
                self.status = Status::Failed;
                self.error = e.to_string();
                Err(e)
            }
        }
    }

    fn play_online(&mut self, station: Station) {
        self.begin(&station);
        self.status = Status::Connecting;
        let tx = Tx {
            generation: self.generation,
            tx: self.events.clone(),
        };
        self.source = Some(Source::Online(Stream::start(station, tx)));
    }

    /// Plays station `id`: over FM when it is a local one and the aerial is
    /// in, else from the internet.
    fn play(&mut self, id: &str) -> std::io::Result<()> {
        if let Some(khz) = id.strip_prefix(FM_PREFIX) {
            let freq = fm_id(khz).ok_or_else(|| std::io::Error::other("no such FM station"))?;
            return self.play_fm(freq, self.fm_station(freq));
        }
        let station = self
            .find(id)
            .ok_or_else(|| std::io::Error::other("no such station"))?;
        match self.fm_for(&station) {
            Some(freq) if route::headset() && Path::new("/dev/fm").exists() => {
                let mut fm = station;
                fm.codec = "FM".into();
                self.play_fm(freq, fm)
            }
            _ => {
                self.play_online(station);
                Ok(())
            }
        }
    }

    /// The last station, or the first local one, when nothing is chosen.
    fn resume(&mut self) -> std::io::Result<()> {
        if let Some(s) = self.station.clone().or_else(|| self.library.last.clone()) {
            return self.play(&s.id);
        }
        let freq = self.band.stations.first().copied().unwrap_or(FIRST);
        self.play_fm(freq, self.fm_station(freq))
    }

    /// The next (or previous) station in the list the station came from;
    /// on FM with no list, the next station on the band.
    fn step(&mut self, forward: bool) -> std::io::Result<()> {
        let current = self
            .station
            .as_ref()
            .map_or_else(String::new, |s| s.id.clone());
        if self.context.len() > 1 {
            let at = self
                .context
                .iter()
                .position(|id| *id == current)
                .unwrap_or(0);
            let n = self.context.len();
            let next = if forward {
                (at + 1) % n
            } else {
                (at + n - 1) % n
            };
            let id = self.context[next].clone();
            return self.play(&id);
        }
        if let Some(fm) = self.tuner() {
            let freq = fm.seek(self.frequency, forward)?;
            return self.play_fm(freq, self.fm_station(freq));
        }
        Ok(())
    }

    /// Runs `work` on the tuner, powering it up for the call if it is off.
    fn with_receiver<R>(
        &mut self,
        work: impl FnOnce(&Fm) -> std::io::Result<R>,
    ) -> std::io::Result<R> {
        if let Some(fm) = self.tuner() {
            return work(fm);
        }
        if let Some(fm) = self.survey.take() {
            fm.power_down().ok();
        }
        let fm = Fm::open()?;
        fm.power_up(self.frequency)?;
        let r = work(&fm);
        fm.power_down().ok();
        r
    }

    fn metadata(&self) -> Dict {
        let mut m = Dict::new();
        let Some(s) = &self.station else { return m };
        let id: String =
            s.id.chars()
                .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
                .collect();
        if let Ok(path) = ObjectPath::try_from(format!("{PATH}/station/s{id}")) {
            put(&mut m, "mpris:trackid", path.into());
        }
        let place = if self.tuner().is_some() {
            mhz(self.frequency)
        } else {
            s.country.clone()
        };
        let (title, artist) = if self.title.is_empty() {
            (s.name.clone(), place)
        } else if self.artist.is_empty() {
            (self.title.clone(), s.name.clone())
        } else {
            (self.title.clone(), self.artist.clone())
        };
        put(&mut m, "xesam:title", title.as_str().into());
        put(&mut m, "xesam:artist", vec![artist.as_str()].into());
        put(&mut m, "xesam:album", s.name.as_str().into());
        let art = if s.favicon.starts_with("http") {
            s.favicon.as_str()
        } else {
            ICON
        };
        put(&mut m, "mpris:artUrl", art.into());
        m
    }
}

#[derive(Clone)]
struct Core {
    radio: Shared<Radio>,
    bus: Connection,
    /// Wakes the RDS reader when FM starts; it sleeps otherwise.
    fm_started: async_channel::Sender<()>,
}

impl Core {
    /// Runs `work`, then tells both interfaces' listeners what changed.
    async fn act(
        &self,
        work: impl FnOnce(&mut Radio) -> std::io::Result<()> + Send + 'static,
    ) -> fdo::Result<()> {
        let r = self.radio.with(work).await;
        self.changed().await;
        r.map_err(|e| fdo::Error::Failed(e.to_string()))
    }

    async fn changed(&self) {
        let (state, sounding, on_fm) = self
            .radio
            .with(|r| (r.state(), r.status.sounding(), r.tuner().is_some()))
            .await;
        if on_fm {
            self.fm_started.try_send(()).ok();
        }
        if let Ok(emitter) = SignalEmitter::new(&self.bus, PATH) {
            Service::state_changed(&emitter, state).await.ok();
        }
        // Only a playing radio is a player: the shell follows the newest.
        if sounding {
            self.bus.request_name(MPRIS_NAME).await.ok();
        } else {
            self.bus.release_name(MPRIS_NAME).await.ok();
        }
        if let Ok(player) = self
            .bus
            .object_server()
            .interface::<_, Player>(MPRIS_PATH)
            .await
        {
            let emitter = player.signal_emitter();
            let p = player.get().await;
            p.playback_status_changed(emitter).await.ok();
            p.metadata_changed(emitter).await.ok();
        }
    }

    async fn catalogue(&self) -> Option<Arc<Catalogue>> {
        self.radio.with(|r| r.catalogue.clone()).await
    }
}

struct Service(Core);

#[interface(name = "org.marathonos.Radio1")]
impl Service {
    async fn get_state(&self) -> Dict {
        self.0.radio.with(|r| r.state()).await
    }

    /// Every place with stations, for the globe: latitude, longitude, its
    /// name and how many stations it has. Empty while the directory loads.
    async fn places(&self) -> Vec<(f64, f64, String, u32)> {
        let Some(c) = self.0.catalogue().await else {
            return Vec::new();
        };
        blocking::unblock(move || {
            c.places
                .iter()
                .map(|p| {
                    let n = u32::try_from(p.stations.len()).unwrap_or(u32::MAX);
                    (p.lat, p.lon, p.label.clone(), n)
                })
                .collect()
        })
        .await
    }

    /// The stations of place `index` (from `Places`), local FM first.
    async fn place_stations(&self, index: u32) -> Vec<Dict> {
        self.0
            .radio
            .with(move |r| {
                let Some(c) = r.catalogue.clone() else {
                    return Vec::new();
                };
                let Some(place) = usize::try_from(index).ok().and_then(|i| c.places.get(i)) else {
                    return Vec::new();
                };
                let stations = place
                    .stations
                    .iter()
                    .map(|&i| c.stations[i].clone())
                    .collect();
                r.list(stations)
            })
            .await
    }

    /// The stations around the phone: those on FM here first (named by
    /// RDS once the band has been scanned), then the nearby internet ones.
    async fn local(&self) -> Vec<Dict> {
        self.0
            .radio
            .with(|r| {
                // One per station: transmitters sending the same RDS code
                // are one station. Named ones first, then the unnamed.
                let mut codes = Vec::new();
                let mut stations = Vec::new();
                let mut unnamed = Vec::new();
                for &f in &r.band.stations {
                    match r.band.names.get(&f) {
                        Some((pi, _)) if *pi != 0 && codes.contains(pi) => {}
                        Some((pi, _)) => {
                            codes.push(*pi);
                            stations.push(r.fm_station(f));
                        }
                        None => unnamed.push(r.fm_station(f)),
                    }
                }
                stations.extend(unnamed);
                if let (Some((lat, lon)), Some(c)) = (r.home, r.catalogue.clone()) {
                    stations.extend(
                        c.near(lat, lon, 100.0)
                            .into_iter()
                            .filter(|s| r.fm_for(s).is_none())
                            .take(80)
                            .cloned(),
                    );
                }
                r.list(stations)
            })
            .await
    }

    /// Stations named like `query`: the located ones on the phone first,
    /// then the rest of the directory.
    async fn search(&self, query: String) -> Vec<Dict> {
        let (catalogue, home) = self.0.radio.with(|r| (r.catalogue.clone(), r.home)).await;
        let mut all: Vec<Station> = match catalogue {
            Some(c) => {
                let q = query.clone();
                blocking::unblock(move || c.search(&q, 40, home).into_iter().cloned().collect())
                    .await
            }
            None => Vec::new(),
        };
        let q = query.clone();
        let online = blocking::unblock(move || catalogue::search_online(&query, 40))
            .await
            .unwrap_or_default();
        for s in online {
            if !all.iter().any(|a| a.id == s.id) {
                all.push(s);
            }
        }
        // Stations the query names before those it only tags, and of those
        // the phone's country's first (the directory's search has no
        // location to go by).
        let words = matching::words(&q);
        self.0
            .radio
            .with(move |r| {
                all.sort_by_key(|s| {
                    let name = matching::words(&s.name);
                    let named = words
                        .iter()
                        .all(|w| name.iter().any(|n| n.starts_with(w.as_str())));
                    (!named, s.cc != r.country)
                });
                r.list(all)
            })
            .await
    }

    async fn favourites(&self) -> Vec<Dict> {
        self.0
            .radio
            .with(|r| {
                let favourites = r.library.favourites.clone();
                r.list(favourites)
            })
            .await
    }

    async fn recents(&self) -> Vec<Dict> {
        self.0
            .radio
            .with(|r| {
                let recents = r.library.recents.clone();
                r.list(recents)
            })
            .await
    }

    async fn set_favourite(&self, id: String, favourite: bool) -> fdo::Result<()> {
        self.0
            .act(move |r| {
                let s = r
                    .find(&id)
                    .ok_or_else(|| std::io::Error::other("no such station"))?;
                r.library.set_favourite(&s, favourite);
                Ok(())
            })
            .await
    }

    /// Plays station `id`; `list` is the list it was chosen from, which
    /// Next and Previous then go through.
    async fn play(&self, id: String, list: Vec<String>) -> fdo::Result<()> {
        self.0
            .act(move |r| {
                if !list.is_empty() {
                    r.context = list;
                }
                r.play(&id)
            })
            .await
    }

    /// Plays FM at `frequency` kHz.
    async fn tune(&self, frequency: i32) -> fdo::Result<()> {
        let freq = u16::try_from(frequency / 10)
            .ok()
            .filter(|f| (fm::LOWEST..=fm::HIGHEST).contains(f))
            .ok_or_else(|| {
                fdo::Error::InvalidArgs(format!("{frequency} kHz is outside the FM band"))
            })?;
        self.0
            .act(move |r| {
                r.context.clear();
                let s = r.fm_station(freq);
                r.play_fm(freq, s)
            })
            .await
    }

    async fn resume(&self) -> fdo::Result<()> {
        self.0.act(Radio::resume).await
    }

    async fn stop(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                r.stop();
                Ok(())
            })
            .await
    }

    async fn next(&self) -> fdo::Result<()> {
        self.0.act(|r| r.step(true)).await
    }

    async fn previous(&self) -> fdo::Result<()> {
        self.0.act(|r| r.step(false)).await
    }

    /// Scans the FM band, then reads each station's RDS name.
    async fn scan(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                r.scanning = true;
                Ok(())
            })
            .await?;
        let r = self
            .0
            .act(|r| {
                let found = r.with_receiver(Fm::scan);
                r.scanning = false;
                r.band.stations = found?;
                if let Some(fm) = r.tuner() {
                    r.frequency = fm.tune(r.frequency)?;
                }
                r.band.save();
                Ok(())
            })
            .await;
        io::spawn(survey(self.0.clone()));
        r
    }

    #[zbus(signal)]
    async fn state_changed(emitter: &SignalEmitter<'_>, state: Dict) -> zbus::Result<()>;
}

/// An internet stream's news: playing, a new title, or given up.
async fn stream_events(core: Core, events: async_channel::Receiver<(u64, Event)>) {
    while let Ok((generation, event)) = events.recv().await {
        let changed = core
            .radio
            .with(move |r| {
                if generation != r.generation {
                    return false;
                }
                match event {
                    Event::Playing => r.status = Status::Playing,
                    Event::Title(t) => {
                        let (artist, title) = icy::split(&t);
                        r.title = title;
                        r.artist = artist.unwrap_or_default();
                    }
                    Event::Failed(e) => {
                        r.source = None;
                        r.status = Status::Failed;
                        r.error = e;
                    }
                }
                true
            })
            .await;
        if changed {
            core.changed().await;
        }
    }
}

/// FM's RDS while it plays: the station's name for the band, its text as
/// what is playing.
async fn rds(core: Core, fm_started: async_channel::Receiver<()>) {
    loop {
        // Asleep until FM plays; then a read a second while it does.
        let on_fm = core.radio.with(|r| r.tuner().is_some()).await;
        if !on_fm && fm_started.recv().await.is_err() {
            return;
        }
        Timer::after(Duration::from_secs(1)).await;
        let changed = core
            .radio
            .with(|r| {
                let rds = r.tuner()?.rds()?;
                let freq = r.frequency;
                if !rds.ps.is_empty() && r.band.names.get(&freq).map(|(_, p)| p) != Some(&rds.ps) {
                    r.band.names.insert(freq, (rds.pi, rds.ps.clone()));
                    r.band.save();
                }
                if r.rds.as_ref() == Some(&rds) {
                    return None;
                }
                let (artist, title) = icy::split(&rds.rt);
                r.title = title;
                r.artist = artist.unwrap_or_default();
                r.rds = Some(rds);
                Some(())
            })
            .await
            .is_some();
        if changed {
            core.changed().await;
        }
    }
}

/// Tunes each scanned station without sound to read its RDS name, giving
/// way to anything played meanwhile.
async fn survey(core: Core) {
    let todo: Vec<u16> = core
        .radio
        .with(|r| {
            r.band
                .stations
                .iter()
                .copied()
                .filter(|f| !r.band.names.contains_key(f))
                .collect()
        })
        .await;
    for freq in todo {
        let tuned = core
            .radio
            .with(move |r| {
                if r.source.is_some() {
                    return false;
                }
                if r.survey.is_none() {
                    let Ok(fm) = Fm::open() else { return false };
                    if fm.power_up(freq).is_err() {
                        return false;
                    }
                    r.survey = Some(fm);
                }
                r.survey.as_ref().is_some_and(|fm| fm.tune(freq).is_ok())
            })
            .await;
        if !tuned {
            break;
        }
        for _ in 0..6 {
            Timer::after(Duration::from_millis(300)).await;
            let named = core
                .radio
                .with(move |r| {
                    let rds = r.survey.as_ref()?.rds().filter(|d| !d.ps.is_empty())?;
                    r.band.names.insert(freq, (rds.pi, rds.ps));
                    Some(())
                })
                .await
                .is_some();
            if named {
                break;
            }
        }
    }
    core.radio
        .with(|r| {
            if let Some(fm) = r.survey.take() {
                fm.power_down().ok();
            }
            r.band.save();
        })
        .await;
    core.changed().await;
}

async fn use_catalogue(core: &Core, stations: Vec<Station>) {
    let c = Arc::new(blocking::unblock(move || Catalogue::new(stations)).await);
    core.radio
        .with(move |r| {
            r.catalogue = Some(c);
            r.catalogue_state = "ready";
        })
        .await;
    core.changed().await;
}

/// The directory from the cache at once, refreshed from Radio Browser when
/// it is a week old or missing.
async fn load_catalogue(core: Core) {
    let cached = blocking::unblock(catalogue::cached).await;
    let stale = cached.as_ref().is_none_or(|(_, stale)| *stale);
    if let Some((stations, _)) = cached {
        use_catalogue(&core, stations).await;
    }
    if !stale {
        return;
    }
    match blocking::unblock(catalogue::fetch).await {
        Ok(stations) => use_catalogue(&core, stations).await,
        Err(e) => {
            log::warn(
                "marathon-radiod",
                format_args!("the station directory: {e}"),
            );
            core.radio
                .with(|r| {
                    if r.catalogue.is_none() {
                        r.catalogue_state = "failed";
                    }
                })
                .await;
            core.changed().await;
        }
    }
}

/// A call takes the capture interface FM plays from (the modem's speech
/// uses it): any call `ModemManager` reports stops the radio.
async fn stop_on_calls(core: Core) {
    let watch = async {
        let system = io::system_bus().await?;
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.ModemManager1.Modem.Voice")
            .member("CallAdded")
            .build()?;
        let mut calls = MessageStream::for_match_rule(rule, &system, None).await?;
        while calls.next().await.is_some() {
            core.act(|r| {
                r.stop();
                Ok(())
            })
            .await
            .ok();
        }
        zbus::Result::Ok(())
    };
    if let Err(e) = watch.await {
        log::warn(
            "marathon-radiod",
            format_args!("not watching for calls: {e}"),
        );
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let (tx, rx) = async_channel::unbounded();
    let band = Band::load();
    let home = home::home();
    let radio = Radio {
        source: None,
        status: Status::Stopped,
        error: String::new(),
        station: None,
        frequency: band.stations.first().copied().unwrap_or(FIRST),
        title: String::new(),
        artist: String::new(),
        rds: None,
        band,
        scanning: false,
        survey: None,
        catalogue: None,
        catalogue_state: "loading",
        library: Library::load(),
        home: home.as_ref().map(|h| (h.lat, h.lon)),
        country: home.map_or_else(String::new, |h| h.country),
        seen: HashMap::new(),
        context: Vec::new(),
        generation: 0,
        events: tx,
    };
    let bus = io::session_bus().await?;
    let (fm_started, fm_wakes) = async_channel::bounded(1);
    let core = Core {
        radio: Shared::new(radio),
        bus: bus.clone(),
        fm_started,
    };
    bus.object_server().at(PATH, Service(core.clone())).await?;
    bus.object_server().at(MPRIS_PATH, Root).await?;
    bus.object_server()
        .at(MPRIS_PATH, Player(core.clone()))
        .await?;
    bus.request_name(BUS_NAME).await?;
    io::spawn(stream_events(core.clone(), rx));
    io::spawn(rds(core.clone(), fm_wakes));
    io::spawn(load_catalogue(core.clone()));
    io::spawn(stop_on_calls(core));
    future::pending().await
}

fn main() -> ExitCode {
    match async_io::block_on(run()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::warn("marathon-radiod", e);
            ExitCode::FAILURE
        }
    }
}
