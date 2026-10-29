//! Marathon's weather service: `org.marathonos.Weather` on the session bus.
//!
//! Forecasts from MET Norway (CC BY 4.0), place names from OpenStreetMap
//! Nominatim, the device's position from `GeoClue2`. D-Bus calls queue
//! commands for the main thread, which takes every queued command before it
//! fetches, so a burst of calls costs one refresh; the last forecast
//! is served from disk at start, and `marathon-bg-weather.timer` calls
//! `Refresh` hourly to move "now" along and refetch once MET's `Expires` has
//! passed.

mod geoclue;
mod http;
mod met;
mod nominatim;
mod solar;
mod store;
mod zones;

use std::process::ExitCode;
use std::sync::mpsc;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::Value;
use zbus::{fdo, interface};

use http::{Failure, Fetched};
use nominatim::Nominatim;
use store::{CacheMeta, Location, Settings, Store};
use zones::Zones;

const BUS_NAME: &str = "org.marathonos.Weather";
const PATH: &str = "/org/marathonos/Weather";
const GEOCLUE_TIMEOUT: Duration = Duration::from_secs(20);
/// After a failed fix, how long refreshes go without asking `GeoClue` again.
const GEOCLUE_RETRY: Duration = Duration::from_mins(10);

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
    published.lock().unwrap_or_else(|_| std::process::abort())
}

struct Weather {
    commands: mpsc::Sender<Command>,
    published: Arc<Mutex<Published>>,
    nominatim: Arc<Nominatim>,
    agent: ureq::Agent,
    zones: Arc<Zones>,
}

fn check_coordinates(latitude: f64, longitude: f64) -> fdo::Result<()> {
    if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
        return Err(fdo::Error::InvalidArgs(
            "latitude/longitude out of range".into(),
        ));
    }
    Ok(())
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
        check_coordinates(latitude, longitude)?;
        self.send(Command::SetLocation(Location {
            name,
            region,
            latitude,
            longitude,
        }))
    }

    fn set_automatic(&self) -> fdo::Result<()> {
        self.send(Command::SetAutomatic)
    }

    /// Any place's forecast, shaped as `Forecast` is for the phone's.
    async fn forecast_at(&self, latitude: f64, longitude: f64) -> fdo::Result<String> {
        check_coordinates(latitude, longitude)?;
        let (agent, zones) = (self.agent.clone(), Arc::clone(&self.zones));
        blocking::unblock(move || {
            let body = match http::fetch_met(&agent, None, latitude, longitude, now()) {
                Ok(Fetched::New { body, .. }) => body,
                Ok(Fetched::NotModified { .. }) => return Err("no forecast".to_owned()),
                Err(Failure::Offline) => return Err("offline".to_owned()),
                Err(Failure::Status(code)) => return Err(format!("HTTP {code}")),
                Err(Failure::Other(message)) => return Err(message),
            };
            let met: Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
            let place = Location {
                name: String::new(),
                region: String::new(),
                latitude,
                longitude,
            };
            let tz = zones.at(latitude, longitude);
            met::forecast(&met, &place, false, &tz, now())
                .map(|f| f.to_string())
                .ok_or_else(|| "no forecast".to_owned())
        })
        .await
        .map_err(fdo::Error::Failed)
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
    zones: Arc<Zones>,
    published: Arc<Mutex<Published>>,
    settings: Settings,
    last_fix: Option<Location>,
    geoclue_failed: Option<Instant>,
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
        let tz = self.zones.at(loc.latitude, loc.longitude);
        met::forecast(body, &loc, automatic, &tz, now())
            .map(|f| f.to_string())
            .unwrap_or_default()
    }

    fn update_fix(&mut self) {
        let (latitude, longitude) = match geoclue::locate(GEOCLUE_TIMEOUT) {
            Ok(fix) => fix,
            Err(e) => {
                self.geoclue_failed = Some(Instant::now());
                return log(&format!("no GeoClue fix ({e}); keeping the last one"));
            }
        };
        self.geoclue_failed = None;
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

    /// Applies a command and everything queued behind it; true when any asks to relocate.
    fn apply_queued(&mut self, first: Command, queued: impl Iterator<Item = Command>) -> bool {
        queued.fold(self.apply(first), |relocate, next| {
            self.apply(next) || relocate
        })
    }

    fn refresh(&mut self, conn: &zbus::Connection, relocate: bool) {
        let automatic = self.settings.manual.is_none();
        let expired = self
            .location()
            .is_none_or(|(loc, _)| self.needs_fetch(&loc));
        let retry = self
            .geoclue_failed
            .is_none_or(|at| at.elapsed() >= GEOCLUE_RETRY);
        if automatic && (relocate || (expired && retry)) {
            // Without a place yet, the choice stays on offer while GeoClue tries.
            let state = if self.location().is_some() {
                "updating"
            } else {
                "no-location"
            };
            publish(conn, &self.published, None, Some(state));
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
    conn: &zbus::Connection,
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
        let iface = zbus::block_on(conn.object_server().interface::<_, Weather>(PATH))?;
        let weather = zbus::block_on(iface.get());
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
        zones: Arc::new(Zones::new()),
        published: Arc::new(Mutex::new(Published {
            forecast: String::new(),
            state: "idle".into(),
        })),
        last_failed: false,
        geoclue_failed: None,
    };
    lock(&daemon.published).forecast = daemon.render();

    let (commands, queue) = mpsc::channel();
    let weather = Weather {
        commands,
        published: Arc::clone(&daemon.published),
        nominatim,
        agent: daemon.agent.clone(),
        zones: Arc::clone(&daemon.zones),
    };
    let conn = match zbus::block_on(
        zbus::connection::Builder::session()
            .serve_at(PATH, weather)
            .name(BUS_NAME)
            .build(),
    ) {
        Ok(conn) => conn,
        Err(e) => {
            log(&format!("cannot serve {BUS_NAME}: {e}"));
            return ExitCode::FAILURE;
        }
    };

    let mut relocate = false;
    loop {
        daemon.refresh(&conn, relocate);
        let Ok(command) = queue.recv() else {
            return ExitCode::FAILURE;
        };
        relocate = daemon.apply_queued(command, queue.try_iter());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn daemon(dir: &std::path::Path) -> Daemon {
        let agent = http::agent();
        Daemon {
            store: Store::at(dir),
            nominatim: Arc::new(Nominatim::new(agent.clone())),
            agent,
            zones: Arc::new(Zones::new()),
            published: Arc::new(Mutex::new(Published {
                forecast: String::new(),
                state: String::new(),
            })),
            settings: Settings::default(),
            last_fix: None,
            geoclue_failed: None,
            met: None,
            last_failed: false,
        }
    }

    fn dublin() -> Location {
        Location {
            name: "Dublin".into(),
            region: "Ireland".into(),
            latitude: 53.35,
            longitude: -6.26,
        }
    }

    #[test]
    fn a_burst_of_commands_is_taken_at_once() {
        let dir = std::env::temp_dir().join(format!("weatherd-queue-{}", std::process::id()));
        let mut d = daemon(&dir);

        let queued = [
            Command::Refresh,
            Command::SetLocation(dublin()),
            Command::Refresh,
        ];
        assert!(!d.apply_queued(Command::Refresh, queued.into_iter()));
        assert_eq!(d.settings.manual, Some(dublin()));

        let queued = [Command::Refresh];
        assert!(d.apply_queued(Command::SetAutomatic, queued.into_iter()));
        assert_eq!(d.settings.manual, None);
        std::fs::remove_dir_all(dir).ok();
    }
}
