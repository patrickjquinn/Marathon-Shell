//! Marathon's weather service: `org.marathonos.Weather` on the session bus.
//!
//! Forecasts from MET Norway (CC BY 4.0), place names from OpenStreetMap
//! Nominatim, the device's position from `GeoClue2`. D-Bus calls queue
//! commands for the main thread, which does all fetching; the last forecast
//! is served from disk at start, and an hourly tick (on the monotonic clock,
//! so it never wakes a suspended device) moves "now" along and refetches
//! once MET's `Expires` has passed.

mod geoclue;
mod http;
mod met;
mod nominatim;
mod solar;
mod store;
mod zones;

use std::process::ExitCode;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::Value;
use zbus::{fdo, interface};

use http::{Failure, Fetched};
use nominatim::Nominatim;
use store::{CacheMeta, Location, Settings, Store};

const BUS_NAME: &str = "org.marathonos.Weather";
const PATH: &str = "/org/marathonos/Weather";
const GEOCLUE_TIMEOUT: Duration = Duration::from_secs(20);

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-weatherd: {message}");
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_secs()).ok())
        .unwrap_or_default()
}

enum Command {
    Refresh,
    SetLocation(Location),
    SetAutomatic,
}

struct Published {
    forecast: String,
    state: String,
}

fn lock(published: &Mutex<Published>) -> MutexGuard<'_, Published> {
    published.lock().unwrap_or_else(PoisonError::into_inner)
}

struct Weather {
    commands: mpsc::Sender<Command>,
    published: Arc<Mutex<Published>>,
    nominatim: Arc<Nominatim>,
}

impl Weather {
    fn send(&self, command: Command) -> fdo::Result<()> {
        self.commands
            .send(command)
            .map_err(|e| fdo::Error::Failed(e.to_string()))
    }
}

#[interface(name = "org.marathonos.Weather1")]
impl Weather {
    #[zbus(property)]
    fn forecast(&self) -> String {
        lock(&self.published).forecast.clone()
    }

    #[zbus(property)]
    fn state(&self) -> String {
        lock(&self.published).state.clone()
    }

    fn refresh(&self) -> fdo::Result<()> {
        self.send(Command::Refresh)
    }

    fn set_location(
        &self,
        name: String,
        region: String,
        latitude: f64,
        longitude: f64,
    ) -> fdo::Result<()> {
        if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
            return Err(fdo::Error::InvalidArgs(
                "latitude/longitude out of range".into(),
            ));
        }
        let timezone = self
            .nominatim
            .searched_country(latitude, longitude)
            .and_then(|country| zones::zone_for(&country, latitude, longitude));
        self.send(Command::SetLocation(Location {
            name,
            region,
            latitude,
            longitude,
            timezone,
        }))
    }

    fn set_automatic(&self) -> fdo::Result<()> {
        self.send(Command::SetAutomatic)
    }

    async fn search(&self, query: String) -> fdo::Result<String> {
        let nominatim = Arc::clone(&self.nominatim);
        let places = blocking::unblock(move || nominatim.search(&query))
            .await
            .map_err(fdo::Error::Failed)?;
        let list: Vec<Value> = places.iter().map(nominatim::Place::to_json).collect();
        Ok(Value::Array(list).to_string())
    }
}

struct Daemon {
    store: Store,
    agent: ureq::Agent,
    nominatim: Arc<Nominatim>,
    published: Arc<Mutex<Published>>,
    settings: Settings,
    last_fix: Option<Location>,
    met: Option<(Value, CacheMeta)>,
    last_failed: bool,
}

impl Daemon {
    /// `(location, automatic)`: the pinned place, else the last `GeoClue` fix.
    fn location(&self) -> Option<(Location, bool)> {
        match &self.settings.manual {
            Some(pinned) => Some((pinned.clone(), false)),
            None => self.last_fix.clone().map(|fix| (fix, true)),
        }
    }

    fn cached_for(&self, loc: &Location) -> Option<&(Value, CacheMeta)> {
        self.met
            .as_ref()
            .filter(|(_, meta)| http::same_point(meta, loc.latitude, loc.longitude))
    }

    fn needs_fetch(&self, loc: &Location) -> bool {
        self.last_failed
            || !self
                .cached_for(loc)
                .is_some_and(|(_, meta)| http::is_fresh(meta, loc.latitude, loc.longitude, now()))
    }

    fn render(&self) -> String {
        let Some((loc, automatic)) = self.location() else {
            return String::new();
        };
        let Some((body, _)) = self.cached_for(&loc) else {
            return String::new();
        };
        let tz = zones::load(loc.timezone.as_deref());
        met::forecast(body, &loc, automatic, &tz, now())
            .map(|f| f.to_string())
            .unwrap_or_default()
    }

    fn update_fix(&mut self) {
        let (latitude, longitude) = match geoclue::locate(GEOCLUE_TIMEOUT) {
            Ok(fix) => fix,
            Err(e) => return log(&format!("no GeoClue fix ({e}); keeping the last one")),
        };
        let named = self.last_fix.as_ref().filter(|fix| {
            !fix.name.is_empty()
                && (fix.latitude - latitude).abs() < 0.01
                && (fix.longitude - longitude).abs() < 0.01
        });
        let (name, region) = match named {
            Some(fix) => (fix.name.clone(), fix.region.clone()),
            None => match self.nominatim.reverse(latitude, longitude) {
                Ok(place) => (place.name, place.region),
                Err(e) => {
                    log(&format!("reverse geocoding failed: {e}"));
                    (String::new(), String::new())
                }
            },
        };
        let fix = Location {
            name,
            region,
            latitude,
            longitude,
            timezone: None,
        };
        if let Err(e) = self.store.save_last_fix(&fix) {
            log(&format!("saving the location: {e}"));
        }
        self.last_fix = Some(fix);
    }

    /// Fetches into the cache and returns the resulting `State`.
    fn fetch(&mut self, loc: &Location) -> String {
        let cached = self.cached_for(loc).map(|(_, meta)| meta);
        let result = http::fetch_met(&self.agent, cached, loc.latitude, loc.longitude, now());
        self.last_failed = true;
        let (body, meta) = match result {
            Ok(Fetched::New { body, meta }) => match serde_json::from_str(&body) {
                Ok(parsed) => {
                    if let Err(e) = self.store.save_forecast(&body, &meta) {
                        log(&format!("saving the forecast: {e}"));
                    }
                    (parsed, meta)
                }
                Err(e) => {
                    log(&format!("unreadable forecast: {e}"));
                    return "error: bad forecast data".into();
                }
            },
            Ok(Fetched::NotModified { meta }) => {
                let Some((body, _)) = self.met.take() else {
                    return "error: no cached forecast".into();
                };
                if let Err(e) = self.store.save_meta(&meta) {
                    log(&format!("saving the forecast: {e}"));
                }
                (body, meta)
            }
            Err(Failure::Offline) => return "offline".into(),
            Err(Failure::Status(code)) => return format!("error: HTTP {code}"),
            Err(Failure::Other(message)) => return format!("error: {message}"),
        };
        self.met = Some((body, meta));
        self.last_failed = false;
        "idle".into()
    }

    fn apply(&mut self, command: Command) -> bool {
        let relocate = match command {
            Command::Refresh => false,
            Command::SetLocation(pinned) => {
                self.settings.manual = Some(pinned);
                false
            }
            Command::SetAutomatic => {
                self.settings.manual = None;
                true
            }
        };
        if let Err(e) = self.store.save_settings(&self.settings) {
            log(&format!("saving the location choice: {e}"));
        }
        relocate
    }

    fn refresh(&mut self, conn: &zbus::blocking::Connection, relocate: bool) {
        let automatic = self.settings.manual.is_none();
        let expired = self
            .location()
            .is_none_or(|(loc, _)| self.needs_fetch(&loc));
        if automatic && (relocate || expired) {
            publish(conn, &self.published, None, Some("updating"));
            self.update_fix();
        }
        let state = match self.location() {
            None => "no-location".to_owned(),
            Some((loc, _)) if self.needs_fetch(&loc) => {
                publish(conn, &self.published, None, Some("updating"));
                self.fetch(&loc)
            }
            Some(_) => "idle".to_owned(),
        };
        publish(conn, &self.published, Some(self.render()), Some(&state));
    }
}

/// Updates the properties and emits `PropertiesChanged` for those that changed.
fn publish(
    conn: &zbus::blocking::Connection,
    published: &Mutex<Published>,
    forecast: Option<String>,
    state: Option<&str>,
) {
    let (forecast_changed, state_changed) = {
        let mut p = lock(published);
        let forecast_changed = forecast.is_some_and(|f| {
            f != p.forecast && {
                p.forecast = f;
                true
            }
        });
        let state_changed = state.is_some_and(|s| {
            s != p.state && {
                s.clone_into(&mut p.state);
                true
            }
        });
        (forecast_changed, state_changed)
    };
    let emit = || -> zbus::Result<()> {
        let iface = conn.object_server().interface::<_, Weather>(PATH)?;
        let weather = iface.get();
        if forecast_changed {
            zbus::block_on(weather.forecast_changed(iface.signal_emitter()))?;
        }
        if state_changed {
            zbus::block_on(weather.state_changed(iface.signal_emitter()))?;
        }
        Ok(())
    };
    if let Err(e) = emit() {
        log(&format!("emitting PropertiesChanged: {e}"));
    }
}

fn until_next_hour() -> Duration {
    Duration::from_secs(3600 - now().rem_euclid(3600).unsigned_abs() + 5)
}

fn main() -> ExitCode {
    let store = Store::from_env();
    let agent = http::agent();
    let nominatim = Arc::new(Nominatim::new(agent.clone()));
    let mut daemon = Daemon {
        settings: store.settings(),
        last_fix: store.last_fix(),
        met: store.forecast(),
        store,
        agent,
        nominatim: Arc::clone(&nominatim),
        published: Arc::new(Mutex::new(Published {
            forecast: String::new(),
            state: "idle".into(),
        })),
        last_failed: false,
    };
    lock(&daemon.published).forecast = daemon.render();

    let (commands, queue) = mpsc::channel();
    let weather = Weather {
        commands,
        published: Arc::clone(&daemon.published),
        nominatim,
    };
    let conn = match zbus::blocking::connection::Builder::session()
        .and_then(|b| b.serve_at(PATH, weather))
        .and_then(|b| b.name(BUS_NAME))
        .and_then(zbus::blocking::connection::Builder::build)
    {
        Ok(conn) => conn,
        Err(e) => {
            log(&format!("cannot serve {BUS_NAME}: {e}"));
            return ExitCode::FAILURE;
        }
    };

    let mut relocate = false;
    loop {
        daemon.refresh(&conn, relocate);
        relocate = match queue.recv_timeout(until_next_hour()) {
            Ok(command) => daemon.apply(command),
            Err(RecvTimeoutError::Timeout) => false,
            Err(RecvTimeoutError::Disconnected) => return ExitCode::FAILURE,
        };
    }
}
