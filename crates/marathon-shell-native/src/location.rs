//! `Location`: the shell's `GeoClue` client, and the shell as `GeoClue`'s agent,
//! as GNOME Shell and Phosh are. `GeoClue` holds every client of a user with
//! no agent, and forgets its agents when it exits, so the agent registers
//! each time the service starts. `GeoClue` is bus-activated and can take 90 s
//! to come up without Wi-Fi or a SIM; nothing here waits on it on the GUI
//! thread.

use crate::i18n::fl;
use std::collections::HashMap;
use std::pin::Pin;

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::{stream, StreamExt};
use zbus::fdo::{self, DBusProxy};
use zbus::message::Header;
use zbus::names::BusName;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue};

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

        #[qinvokable]
        fn start(self: &Location);
        #[qinvokable]
        fn stop(self: &Location);
    }

    impl cxx_qt::Threading for Location {}
    impl cxx_qt::Initialize for Location {}
}

use qobject::Location;

#[derive(Default)]
pub struct LocationRust {
    available: bool,
    active: bool,
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    altitude: f64,
    speed: f64,
    heading: f64,
    timestamp: i64,
    actor: Option<Sender<bool>>,
}

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
        self.as_mut().rust_mut().actor = Some(tx);
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
        ipc::on_gui(&self.qt, |obj| obj.start()).await
    }

    async fn stop(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Location", &["location"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.stop()).await
    }

    async fn get_location(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<State> {
        ipc::admit(&h, "Location", &["location"]).await?;
        ipc::on_gui(&self.qt, |obj| fix(&obj)).await
    }
}

impl Location {
    fn start(&self) {
        if let Some(actor) = &self.actor {
            actor.try_send(true).ok();
        }
    }

    fn stop(&self) {
        if let Some(actor) = &self.actor {
            actor.try_send(false).ok();
        }
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
const EXACT: u32 = 8;
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

enum Event {
    Wanted(bool),
    Closed,
    Restarted(bool),
    Updated(OwnedObjectPath),
}

#[allow(
    clippy::too_many_lines,
    reason = "the GeoClue connection and event-loop state belong to one actor task"
)]
async fn run(qt: Qt, wanted: Receiver<bool>) {
    let bus = match io::system_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("location", format_args!("no system bus: {e}")),
    };
    if let Err(e) = bus
        .object_server()
        .at("/org/freedesktop/GeoClue2/Agent", Agent)
        .await
    {
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
    if running {
        add_agent(&bus).await;
    }
    let owners = match dbus
        .receive_name_owner_changed_with_args(&[(0, GEOCLUE)])
        .await
    {
        Ok(s) => s
            .filter_map(|s| Some(Event::Restarted(s.args().ok()?.new_owner().is_some())))
            .boxed(),
        Err(_) => stream::empty().boxed(),
    };
    let (new_fixes, fixes) = async_channel::bounded(8);
    // The shell locates from the start, until something stops it.
    let events = stream::once(Event::Wanted(true))
        .chain(wanted.map(Event::Wanted))
        .chain(stream::once(Event::Closed))
        .or(owners)
        .or(fixes.map(Event::Updated));
    let mut events = std::pin::pin!(events);
    let (mut want, mut active) = (false, false);
    let mut client: Option<ClientProxy<'static>> = None;
    while let Some(event) = events.next().await {
        match event {
            Event::Closed => break,
            Event::Wanted(on) => want = on,
            Event::Restarted(true) => add_agent(&bus).await,
            Event::Restarted(false) => {
                client = None;
                active = false;
            }
            Event::Updated(path) => {
                let props = properties(&bus, &path).await;
                let fix = Fix::from_properties(&props);
                qt.queue(move |obj| obj.apply(fix)).ok();
                continue;
            }
        }
        if want && client.is_none() {
            client = new_client(&bus, &new_fixes).await;
            if client.is_none() {
                qt.queue(|obj| obj.error(&QString::from(fl!("location-client-failed"))))
                    .ok();
            }
        }
        let Some(c) = &client else { continue };
        if want != active {
            let result = if want {
                c.start().await
            } else {
                c.stop().await
            };
            match result {
                Ok(()) => active = want,
                Err(e) => {
                    log::warn(
                        "location",
                        format_args!("{}: {e}", if want { "start" } else { "stop" }),
                    );
                    if want {
                        qt.queue(|obj| {
                            obj.error(&QString::from(fl!("location-start-failed")));
                        })
                        .ok();
                    }
                }
            }
        }
        qt.queue(move |mut obj| set!(obj, active, active_changed, active))
            .ok();
    }
}

async fn add_agent(bus: &zbus::Connection) {
    let added = async {
        ManagerProxy::new(bus)
            .await?
            .add_agent("marathon-shell")
            .await
    };
    if let Err(e) = added.await {
        log::warn("location", format_args!("AddAgent: {e}"));
    }
}

/// A client for the shell, its fixes forwarded to `updates`.
async fn new_client(
    bus: &zbus::Connection,
    updates: &Sender<OwnedObjectPath>,
) -> Option<ClientProxy<'static>> {
    let made = async {
        let path = ManagerProxy::new(bus).await?.get_client().await?;
        let client = ClientProxy::builder(bus)
            .path(path)?
            .cache_properties(zbus::proxy::CacheProperties::No)
            .build()
            .await?;
        client.set_desktop_id("org.marathon.Shell").await?;
        client.set_requested_accuracy_level(EXACT).await?;
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
        EXACT
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use zbus::zvariant::{OwnedValue, Value};

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
