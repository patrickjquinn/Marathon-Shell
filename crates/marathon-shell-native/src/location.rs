//! `Location`: the shell's `GeoClue` client, and the shell as `GeoClue`'s agent,
//! as GNOME Shell and Phosh are. `GeoClue` holds every client of a user with
//! no agent, and forgets its agents when it exits, so the agent registers
//! each time the service starts. `GeoClue` is bus-activated and can take 90 s
//! to come up without Wi-Fi or a SIM; nothing here waits on it on the GUI
//! thread. With location off, as GNOME Shell does, the agent's maximum
//! accuracy is none, so `GeoClue` serves no client at all.
//!
//! On its own the shell takes one city-level fix an hour, for the time zone,
//! which needs no satellites. Exact fixes, and so GNSS, run only while an app
//! holds a `Start`, until it calls `Stop` or leaves the bus.

use crate::i18n::fl;
use std::collections::{HashMap, HashSet};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::{stream, StreamExt};
use zbus::fdo::{self, DBusProxy};
use zbus::message::Header;
use zbus::names::BusName;
use zbus::{ObjectPath, OwnedObjectPath, OwnedVariant as OwnedValue};

use crate::ipc::{self, value, State};
use crate::{io, log, permissions};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, active, READ, NOTIFY)]
        /// The system's location switch.
        #[qproperty(bool, enabled, READ, WRITE = set_enabled, NOTIFY)]
        #[qproperty(f64, latitude, READ, NOTIFY = location_changed)]
        #[qproperty(f64, longitude, READ, NOTIFY = location_changed)]
        #[qproperty(f64, accuracy, READ, NOTIFY = location_changed)]
        #[qproperty(f64, altitude, READ, NOTIFY = location_changed)]
        #[qproperty(f64, speed, READ, NOTIFY = location_changed)]
        #[qproperty(f64, heading, READ, NOTIFY = location_changed)]
        /// Milliseconds since the epoch.
        #[qproperty(i64, timestamp, READ, NOTIFY = location_changed)]
        type Location = super::LocationRust;

        #[qsignal]
        #[cxx_name = "locationChanged"]
        fn location_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn error(self: Pin<&mut Self>, message: &QString);

        #[cxx_name = "setEnabled"]
        fn set_enabled(self: Pin<&mut Location>, enabled: bool);
    }

    impl cxx_qt::Threading for Location {}
    impl cxx_qt::Initialize for Location {}
}

use qobject::Location;

pub struct LocationRust {
    available: bool,
    active: bool,
    enabled: bool,
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    altitude: f64,
    speed: f64,
    heading: f64,
    timestamp: i64,
    actor: Option<Sender<Ask>>,
}

impl Default for LocationRust {
    fn default() -> Self {
        Self {
            available: false,
            active: false,
            enabled: true,
            latitude: 0.0,
            longitude: 0.0,
            accuracy: 0.0,
            altitude: 0.0,
            speed: 0.0,
            heading: 0.0,
            timestamp: 0,
            actor: None,
        }
    }
}

/// The switch, for the agent, which answers `GeoClue` on the I/O thread.
static ENABLED: AtomicBool = AtomicBool::new(true);

#[derive(Clone, Copy, Default)]
struct Fix {
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    altitude: f64,
    speed: f64,
    heading: f64,
    timestamp: i64,
}

impl cxx_qt::Initialize for Location {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(8);
        io::spawn(run(self.qt_thread(), rx));
        self.as_mut().rust_mut().actor = Some(tx.clone());
        self.as_mut()
            .on_location_changed(|obj| ipc::signal("Location", "LocationChanged", (fix(&obj),)))
            .release();
        self.as_mut()
            .on_active_changed(|obj| ipc::signal("Location", "activeChanged", (obj.active,)))
            .release();
        ipc::export(
            "Location",
            Location1 {
                qt: self.qt_thread(),
                actor: tx,
            },
        );
    }
}

fn fix(location: &Location) -> State {
    State::from([
        ("latitude".to_owned(), value(location.latitude)),
        ("longitude".to_owned(), value(location.longitude)),
        ("accuracy".to_owned(), value(location.accuracy)),
        ("altitude".to_owned(), value(location.altitude)),
        ("speed".to_owned(), value(location.speed)),
        ("heading".to_owned(), value(location.heading)),
        ("timestamp".to_owned(), value(location.timestamp)),
    ])
}

struct Location1 {
    qt: cxx_qt::CxxQtThread<Location>,
    actor: Sender<Ask>,
}

impl Location1 {
    async fn tell(&self, h: &Header<'_>, hold: bool) -> fdo::Result<()> {
        let sender = h
            .sender()
            .ok_or_else(|| fdo::Error::AccessDenied("Unknown caller".into()))?
            .to_string();
        let ask = if hold {
            Ask::Hold(sender)
        } else {
            Ask::Release(sender)
        };
        self.actor
            .send(ask)
            .await
            .map_err(|_stopping| fdo::Error::Failed("the shell is stopping".into()))
    }
}

#[zbus::interface(name = "org.marathonos.Shell.Location1")]
impl Location1 {
    async fn is_available(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        ipc::admit(&h, "Location", &["location"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.available).await
    }

    async fn is_active(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        ipc::admit(&h, "Location", &["location"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.active).await
    }

    async fn start(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Location", &["location"]).await?;
        if !ENABLED.load(Ordering::Relaxed) {
            return Err(fdo::Error::AccessDenied("Location is off".to_owned()));
        }
        self.tell(&h, true).await
    }

    async fn stop(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Location", &["location"]).await?;
        self.tell(&h, false).await
    }

    async fn get_location(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<State> {
        ipc::admit(&h, "Location", &["location"]).await?;
        ipc::on_gui(&self.qt, |obj| fix(&obj)).await
    }
}

impl Location {
    fn set_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        set!(self, enabled, enabled_changed, enabled);
        ENABLED.store(enabled, Ordering::Relaxed);
        if let Some(actor) = &self.actor {
            actor.try_send(Ask::Enabled(enabled)).ok();
        }
        io::spawn(async {
            let Ok(bus) = io::system_bus().await else {
                return;
            };
            let Ok(agent) = bus.object_server().interface::<_, Agent>(AGENT).await else {
                return;
            };
            let changed = agent
                .get()
                .await
                .max_accuracy_level_changed(agent.signal_emitter())
                .await;
            if let Err(e) = changed {
                log::warn("location", format_args!("MaxAccuracyLevel: {e}"));
            }
        });
    }

    fn apply(mut self: Pin<&mut Self>, fix: Fix) {
        let mut rust = self.as_mut().rust_mut();
        rust.latitude = fix.latitude;
        rust.longitude = fix.longitude;
        rust.accuracy = fix.accuracy;
        rust.altitude = fix.altitude;
        rust.speed = fix.speed;
        rust.heading = fix.heading;
        rust.timestamp = fix.timestamp;
        self.location_changed();
    }
}

impl Fix {
    fn from_properties(props: &HashMap<String, OwnedValue>) -> Self {
        let number = |key: &str| {
            props
                .get(key)
                .and_then(|v| v.downcast_ref::<f64>().ok())
                .unwrap_or(0.0)
        };
        let (secs, micros) = props
            .get("Timestamp")
            .and_then(|v| <(u64, u64)>::try_from(v.try_clone().ok()?).ok())
            .unwrap_or_default();
        let timestamp = secs.saturating_mul(1000).saturating_add(micros / 1000);
        Self {
            latitude: number("Latitude"),
            longitude: number("Longitude"),
            accuracy: number("Accuracy"),
            altitude: number("Altitude"),
            speed: number("Speed"),
            heading: number("Heading"),
            timestamp: i64::try_from(timestamp).unwrap_or(i64::MAX),
        }
    }
}

const GEOCLUE: &str = "org.freedesktop.GeoClue2";
const AGENT: &str = "/org/freedesktop/GeoClue2/Agent";
const CITY: u32 = 4;
const EXACT: u32 = 8;
/// How often the shell takes its own fix, and how long it waits for one.
const RELOCATE: Duration = Duration::from_hours(1);
const GIVE_UP: Duration = Duration::from_mins(2);
/// `GeoClue`'s apps that locate without asking: the shell, weatherd, the
/// portal (which asks the user itself) and deckardd (Android asks per app).
const SYSTEM: [&str; 4] = [
    "org.marathon.Shell",
    "marathon-weather",
    "xdg-desktop-portal",
    "org.marathonos.Deckard",
];

#[zbus::proxy(
    interface = "org.freedesktop.GeoClue2.Manager",
    default_service = "org.freedesktop.GeoClue2",
    default_path = "/org/freedesktop/GeoClue2/Manager"
)]
trait Manager {
    fn get_client(&self) -> zbus::Result<OwnedObjectPath>;
    fn add_agent(&self, id: &str) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.GeoClue2.Client",
    default_service = "org.freedesktop.GeoClue2"
)]
trait Client {
    fn start(&self) -> zbus::Result<()>;
    fn stop(&self) -> zbus::Result<()>;
    #[zbus(property)]
    fn desktop_id(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn set_desktop_id(&self, id: &str) -> zbus::Result<()>;
    #[zbus(property)]
    fn requested_accuracy_level(&self) -> zbus::Result<u32>;
    #[zbus(property)]
    fn set_requested_accuracy_level(&self, level: u32) -> zbus::Result<()>;
    #[zbus(signal)]
    fn location_updated(
        &self,
        old_location: ObjectPath<'_>,
        new_location: ObjectPath<'_>,
    ) -> zbus::Result<()>;
}

type Qt = cxx_qt::CxxQtThread<Location>;

/// What the actor is told.
enum Ask {
    Enabled(bool),
    /// An app, by its bus name, wants exact fixes.
    Hold(String),
    Release(String),
}

enum Event {
    Ask(Ask),
    Closed,
    Restarted(bool),
    Updated(OwnedObjectPath),
    Left(String),
    Relocate,
    GiveUp(u32),
}

#[allow(
    clippy::too_many_lines,
    reason = "the GeoClue connection and event-loop state belong to one actor task"
)]
async fn run(qt: Qt, asks: Receiver<Ask>) {
    let bus = match io::system_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("location", format_args!("no system bus: {e}")),
    };
    if let Err(e) = bus.object_server().at(AGENT, Agent).await {
        log::warn("location", format_args!("cannot export the agent: {e}"));
    }
    let Ok(dbus) = DBusProxy::new(&bus).await else {
        return;
    };
    let running = match BusName::from_static_str(GEOCLUE) {
        Ok(name) => dbus.name_has_owner(name).await.unwrap_or(false),
        Err(_) => false,
    };
    let activatable = running
        || dbus
            .list_activatable_names()
            .await
            .unwrap_or_default()
            .iter()
            .any(|n| n.as_str() == GEOCLUE);
    qt.queue(move |mut obj| set!(obj, available, available_changed, activatable))
        .ok();
    if !activatable {
        return;
    }
    // Only if GeoClue already runs: registering would start it just to sit idle.
    let mut agent = running && add_agent(&bus).await;
    let owners = match dbus
        .receive_name_owner_changed_with_args(&[(0, GEOCLUE)])
        .await
    {
        Ok(s) => s
            .filter_map(|s| Some(Event::Restarted(s.args().ok()?.new_owner().is_some())))
            .boxed(),
        Err(_) => stream::empty().boxed(),
    };
    let session = match io::session_bus().await {
        Ok(session) => DBusProxy::new(&session).await.ok(),
        Err(_) => None,
    };
    let left = match &session {
        Some(session) => match session.receive_name_owner_changed().await {
            Ok(s) => s
                .filter_map(|s| {
                    let args = s.args().ok()?;
                    let name = args.name().to_string();
                    (args.new_owner().is_none() && name.starts_with(':'))
                        .then_some(Event::Left(name))
                })
                .boxed(),
            Err(_) => stream::empty().boxed(),
        },
        None => stream::empty().boxed(),
    };
    let (new_fixes, fixes) = async_channel::bounded(8);
    let (give_up, rounds_over) = async_channel::bounded(1);
    let events = stream::once(Event::Relocate)
        .chain(asks.map(Event::Ask))
        .chain(stream::once(Event::Closed))
        .or(owners)
        .or(left)
        .or(fixes.map(Event::Updated))
        .or(Timer::interval(RELOCATE).map(|_| Event::Relocate))
        .or(rounds_over.map(Event::GiveUp));
    let mut events = std::pin::pin!(events);
    let mut holders = HashSet::new();
    // The shell's own fix, while it waits for one.
    let (mut own, mut rounds) = (None, 0u32);
    let mut level = 0;
    let mut client: Option<ClientProxy<'static>> = None;
    while let Some(event) = events.next().await {
        match event {
            Event::Closed => break,
            Event::Relocate | Event::Ask(Ask::Enabled(true)) => {
                relocate(&mut own, &mut rounds, &give_up);
            }
            Event::Ask(Ask::Enabled(false)) => {}
            Event::GiveUp(round) => {
                if own == Some(round) {
                    own = None;
                }
            }
            Event::Ask(Ask::Hold(name)) => {
                holders.insert(name);
            }
            Event::Ask(Ask::Release(name)) | Event::Left(name) => {
                holders.remove(&name);
            }
            Event::Restarted(true) => agent = add_agent(&bus).await,
            Event::Restarted(false) => {
                agent = false;
                client = None;
                level = 0;
            }
            Event::Updated(path) => {
                let props = properties(&bus, &path).await;
                let fix = Fix::from_properties(&props);
                qt.queue(move |obj| obj.apply(fix)).ok();
                own = None;
            }
        }
        let wanted = if !ENABLED.load(Ordering::Relaxed) {
            0
        } else if !holders.is_empty() {
            EXACT
        } else if own.is_some() {
            CITY
        } else {
            0
        };
        if wanted == level {
            continue;
        }
        if wanted > 0 && client.is_none() {
            // GeoClue answers no GetClient of ours until our agent is in, and
            // this loop is what registers it.
            if !agent {
                agent = add_agent(&bus).await;
            }
            client = new_client(&bus, &new_fixes).await;
            if client.is_none() {
                qt.queue(|obj| obj.error(&QString::from(fl!("location-client-failed"))))
                    .ok();
            }
        }
        let Some(c) = &client else { continue };
        if level > 0 {
            match c.stop().await {
                Ok(()) => level = 0,
                Err(e) => log::warn("location", format_args!("stop: {e}")),
            }
        }
        if wanted > 0 && level == 0 {
            let started = async {
                c.set_requested_accuracy_level(wanted).await?;
                c.start().await
            };
            match started.await {
                Ok(()) => level = wanted,
                Err(e) => {
                    log::warn("location", format_args!("start: {e}"));
                    qt.queue(|obj| obj.error(&QString::from(fl!("location-start-failed"))))
                        .ok();
                }
            }
        }
        let active = level > 0;
        qt.queue(move |mut obj| set!(obj, active, active_changed, active))
            .ok();
    }
}

/// Starts a round of the shell's own fix, given up after `GIVE_UP`.
fn relocate(own: &mut Option<u32>, rounds: &mut u32, give_up: &Sender<u32>) {
    if own.is_some() || !ENABLED.load(Ordering::Relaxed) {
        return;
    }
    *rounds = rounds.wrapping_add(1);
    let round = *rounds;
    *own = Some(round);
    let give_up = give_up.clone();
    io::spawn(async move {
        Timer::after(GIVE_UP).await;
        give_up.send(round).await.ok();
    });
}

async fn add_agent(bus: &zbus::Connection) -> bool {
    let added = async {
        ManagerProxy::new(bus)
            .await?
            .add_agent("marathon-shell")
            .await
    };
    added
        .await
        .map_err(|e| log::warn("location", format_args!("AddAgent: {e}")))
        .is_ok()
}

/// A client for the shell, its fixes forwarded to `updates`.
async fn new_client(
    bus: &zbus::Connection,
    updates: &Sender<OwnedObjectPath>,
) -> Option<ClientProxy<'static>> {
    let made = async {
        let path = ManagerProxy::new(bus).await?.get_client().await?;
        let client = ClientProxy::builder(bus)
            .path(path)
            .cache_properties(zbus::proxy::CacheProperties::No)
            .build()
            .await?;
        client.set_desktop_id("org.marathon.Shell").await?;
        let mut fixes = client.receive_location_updated().await?;
        let updates = updates.clone();
        io::spawn(async move {
            while let Some(signal) = fixes.next().await {
                let Ok(args) = signal.args() else { continue };
                if updates
                    .send(OwnedObjectPath::from(args.new_location().clone()))
                    .await
                    .is_err()
                {
                    return;
                }
            }
        });
        zbus::Result::Ok(client)
    };
    made.await
        .map_err(|e| log::warn("location", format_args!("GetClient: {e}")))
        .ok()
}

async fn properties(bus: &zbus::Connection, path: &OwnedObjectPath) -> HashMap<String, OwnedValue> {
    let reply = bus
        .call_method(
            Some(GEOCLUE),
            path,
            Some("org.freedesktop.DBus.Properties"),
            "GetAll",
            &("org.freedesktop.GeoClue2.Location",),
        )
        .await;
    reply
        .and_then(|m| m.body().deserialize())
        .unwrap_or_default()
}

/// `GeoClue`'s agent: the system's apps locate freely, the rest by the
/// shell's permissions.
struct Agent;

#[zbus::interface(name = "org.freedesktop.GeoClue2.Agent")]
impl Agent {
    #[allow(clippy::unused_self, reason = "a D-Bus method")]
    fn authorize_app(&self, desktop_id: &str, requested_accuracy_level: u32) -> (bool, u32) {
        if !ENABLED.load(Ordering::Relaxed) {
            return (false, 0);
        }
        let allowed = SYSTEM.contains(&desktop_id) || permissions::has(desktop_id, "location");
        if !allowed {
            permissions::ask_if_undecided(desktop_id, &["location".to_owned()]);
            log::warn("location", format_args!("refused location to {desktop_id}"));
        }
        (
            allowed,
            if allowed {
                requested_accuracy_level.min(EXACT)
            } else {
                0
            },
        )
    }

    #[zbus(property)]
    #[allow(clippy::unused_self, reason = "a D-Bus property")]
    fn max_accuracy_level(&self) -> u32 {
        if ENABLED.load(Ordering::Relaxed) {
            EXACT
        } else {
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use zbus::{OwnedVariant as OwnedValue, Variant as Value};

    use super::Fix;

    #[test]
    fn a_fix_reads_geoclues_timestamp() {
        let mut props: HashMap<String, OwnedValue> = HashMap::new();
        let mut put = |k: &str, v: Value<'_>| {
            props.insert(
                k.to_owned(),
                v.try_to_owned().unwrap_or_else(|_| OwnedValue::from(0u8)),
            )
        };
        put("Latitude", Value::from(53.35));
        put("Longitude", Value::from(-6.26));
        put("Timestamp", Value::from((1_792_236_376u64, 250_000u64)));
        let fix = Fix::from_properties(&props);
        assert!((fix.latitude - 53.35).abs() < 1e-9 && (fix.longitude + 6.26).abs() < 1e-9);
        assert_eq!(fix.timestamp, 1_792_236_376_250);
    }
}
