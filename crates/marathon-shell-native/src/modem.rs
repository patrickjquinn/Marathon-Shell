//! `ModemManagerCpp`: the modem's state for the status bar, Quick Settings
//! and the emergency-call affordances, mobile data, network modes and cell
//! broadcasts. One `ModemManager` object cache on the I/O thread: the managed
//! objects give every interface's properties at once, and the modem's
//! `PropertiesChanged` carries each change, so nothing is read again.

use std::collections::HashMap;
use std::pin::Pin;
use std::time::{SystemTime, UNIX_EPOCH};

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use futures_lite::{future, stream, StreamExt};
use zbus::fdo::{DBusProxy, ObjectManagerProxy, PropertiesProxy};
use zbus::message::Type as MessageType;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::{MatchRule, MessageStream};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, modem_available, cxx_name = "modemAvailable", READ, NOTIFY)]
        #[qproperty(bool, modem_enabled, cxx_name = "modemEnabled", READ, NOTIFY)]
        #[qproperty(i32, signal_strength, cxx_name = "signalStrength", READ, NOTIFY)]
        #[qproperty(bool, registered, READ, NOTIFY)]
        #[qproperty(QString, operator_name, cxx_name = "operatorName", READ, NOTIFY)]
        #[qproperty(QString, network_type, cxx_name = "networkType", READ, NOTIFY)]
        #[qproperty(bool, roaming, READ, NOTIFY)]
        #[qproperty(bool, sim_present, cxx_name = "simPresent", READ, NOTIFY)]
        #[qproperty(bool, data_enabled, cxx_name = "dataEnabled", READ, NOTIFY)]
        #[qproperty(bool, data_roaming_allowed, cxx_name = "dataRoamingAllowed", READ, WRITE = set_data_roaming_allowed, NOTIFY)]
        #[qproperty(QList_QVariant, supported_modes, cxx_name = "supportedModes", READ, NOTIFY = modes_changed)]
        #[qproperty(u32, current_modes, cxx_name = "allowedModes", READ, NOTIFY)]
        #[qproperty(bool, emergency_only, cxx_name = "emergencyOnly", READ, NOTIFY)]
        #[qproperty(QStringList, sim_emergency_numbers, cxx_name = "simEmergencyNumbers", READ, NOTIFY)]
        /// Cell broadcasts not yet acknowledged, newest last.
        #[qproperty(QList_QVariant, active_broadcasts, cxx_name = "activeBroadcasts", READ, NOTIFY)]
        type ModemManagerCpp = super::ModemRust;

        #[qsignal]
        #[cxx_name = "modesChanged"]
        fn modes_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "broadcastReceived"]
        fn broadcast_received(self: Pin<&mut Self>, broadcast: &QMap_QString_QVariant);

        #[cxx_name = "setDataRoamingAllowed"]
        fn set_data_roaming_allowed(self: Pin<&mut ModemManagerCpp>, allowed: bool);
        #[qinvokable]
        fn enable(self: &ModemManagerCpp);
        #[qinvokable]
        fn disable(self: &ModemManagerCpp);
        #[qinvokable]
        #[cxx_name = "enableData"]
        fn enable_data(self: Pin<&mut ModemManagerCpp>);
        #[qinvokable]
        #[cxx_name = "disableData"]
        fn disable_data(self: Pin<&mut ModemManagerCpp>);
        /// One of `supportedModes`, each a ModemManager `MMModemMode` mask.
        #[qinvokable]
        #[cxx_name = "setAllowedModes"]
        fn set_allowed_modes(self: &ModemManagerCpp, allowed: u32);
        #[qinvokable]
        fn acknowledge(self: Pin<&mut ModemManagerCpp>, path: &QString);
    }

    impl cxx_qt::Threading for ModemManagerCpp {}
    impl cxx_qt::Initialize for ModemManagerCpp {}
}

use qobject::ModemManagerCpp;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct ModemRust {
    available: bool,
    modem_available: bool,
    modem_enabled: bool,
    signal_strength: i32,
    registered: bool,
    operator_name: QString,
    network_type: QString,
    roaming: bool,
    sim_present: bool,
    data_enabled: bool,
    data_roaming_allowed: bool,
    supported_modes: QList<QVariant>,
    current_modes: u32,
    emergency_only: bool,
    sim_emergency_numbers: QStringList,
    active_broadcasts: QList<QVariant>,
    broadcasts: Vec<Broadcast>,
    actor: Option<Sender<Command>>,
}

enum Command {
    Enable(bool),
    Data(bool, bool),
    Modes(u32),
}

/// Sets a property and emits its change signal if it changed.
macro_rules! set {
    ($obj:expr, $field:ident, $changed:ident, $value:expr) => {{
        let value = $value;
        if $obj.$field != value {
            $obj.as_mut().rust_mut().$field = value;
            $obj.as_mut().$changed();
        }
    }};
}

impl cxx_qt::Initialize for ModemManagerCpp {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(16);
        io::spawn(run(self.qt_thread(), rx));
        self.as_mut().rust_mut().actor = Some(tx);
    }
}

impl ModemManagerCpp {
    fn send(&self, command: Command) {
        if !self.modem_available {
            return;
        }
        if let Some(actor) = &self.actor {
            actor.try_send(command).ok();
        }
    }

    fn enable(&self) {
        self.send(Command::Enable(true));
    }

    fn disable(&self) {
        self.send(Command::Enable(false));
    }

    // Optimistic: the tile answers at once, the modem's state confirms.
    fn enable_data(mut self: Pin<&mut Self>) {
        self.send(Command::Data(true, self.data_roaming_allowed));
        set!(self, data_enabled, data_enabled_changed, true);
    }

    fn disable_data(mut self: Pin<&mut Self>) {
        self.send(Command::Data(false, false));
        set!(self, data_enabled, data_enabled_changed, false);
    }

    fn set_allowed_modes(&self, allowed: u32) {
        self.send(Command::Modes(allowed));
    }

    fn set_data_roaming_allowed(mut self: Pin<&mut Self>, allowed: bool) {
        set!(self, data_roaming_allowed, data_roaming_allowed_changed, allowed);
        if !allowed && self.roaming && self.data_enabled {
            self.disable_data();
        }
    }

    fn acknowledge(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        self.as_mut().rust_mut().broadcasts.retain(|b| b.path != path);
        self.publish_broadcasts();
    }

    fn apply(mut self: Pin<&mut Self>, view: &View) {
        set!(self, available, available_changed, view.daemon);
        set!(self, modem_available, modem_available_changed, view.modem);
        set!(self, modem_enabled, modem_enabled_changed, view.enabled);
        set!(self, data_enabled, data_enabled_changed, view.data);
        set!(self, signal_strength, signal_strength_changed, view.strength);
        set!(self, registered, registered_changed, view.registered);
        set!(self, roaming, roaming_changed, view.roaming);
        set!(self, sim_present, sim_present_changed, view.sim);
        set!(self, emergency_only, emergency_only_changed, view.emergency_only);
        if !view.operator.is_empty() {
            set!(self, operator_name, operator_name_changed, QString::from(view.operator.as_str()));
        }
        set!(self, network_type, network_type_changed, QString::from(view.network_type));
        let numbers = QStringList::from(&view.emergency_numbers.iter().map(|n| QString::from(n.as_str())).collect::<QList<QString>>());
        set!(self, sim_emergency_numbers, sim_emergency_numbers_changed, numbers);
        let modes: QList<QVariant> = view.modes.iter().map(QVariant::from).collect();
        let allowed = view.allowed;
        if self.supported_modes != modes || self.current_modes != allowed {
            let mut rust = self.as_mut().rust_mut();
            rust.supported_modes = modes;
            rust.current_modes = allowed;
            self.as_mut().current_modes_changed();
            self.as_mut().modes_changed();
        }
    }

    fn broadcast(mut self: Pin<&mut Self>, broadcast: Broadcast) {
        self.as_mut().broadcast_received(&broadcast.to_map());
        self.as_mut().rust_mut().broadcasts.push(broadcast);
        self.publish_broadcasts();
    }

    fn broadcast_gone(mut self: Pin<&mut Self>, path: &str) {
        self.as_mut().rust_mut().broadcasts.retain(|b| b.path != path);
        self.publish_broadcasts();
    }

    fn publish_broadcasts(mut self: Pin<&mut Self>) {
        let list: QList<QVariant> = self.broadcasts.iter().map(|b| QVariant::from(&b.to_map())).collect();
        set!(self, active_broadcasts, active_broadcasts_changed, list);
    }
}

/// The modem as the shell shows it.
#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties it sets")]
struct View {
    daemon: bool,
    modem: bool,
    enabled: bool,
    data: bool,
    strength: i32,
    registered: bool,
    roaming: bool,
    sim: bool,
    emergency_only: bool,
    operator: String,
    network_type: &'static str,
    emergency_numbers: Vec<String>,
    modes: Vec<u32>,
    allowed: u32,
}

/// The modem's properties across its interfaces, as `ModemManager` last said.
#[derive(Default)]
struct Snapshot {
    path: Option<OwnedObjectPath>,
    sim: Option<OwnedObjectPath>,
    state: i32,
    quality: u32,
    rssi: f64,
    access: u32,
    operator: String,
    registration: u32,
    emergency_only: bool,
    emergency_numbers: Vec<String>,
    supported: Vec<(u32, u32)>,
    current: u32,
}

// ModemManager's MM_MODEM_MODE_CS: calls, not a choice of data mode.
const CIRCUIT_SWITCHED: u32 = 1;

impl Snapshot {
    fn set(&mut self, name: &str, value: &Value<'_>) {
        let owned = || value.try_to_owned().ok();
        match name {
            "Snapshot" => self.state = value.downcast_ref().unwrap_or(self.state),
            "Sim" => self.sim = owned().and_then(|v| OwnedObjectPath::try_from(v).ok()).filter(|p| p.as_str() != "/"),
            "SignalQuality" => self.quality = owned().and_then(|v| <(u32, bool)>::try_from(v).ok()).map_or(self.quality, |q| q.0),
            "Rssi" => self.rssi = value.downcast_ref().unwrap_or(self.rssi),
            "AccessTechnologies" => self.access = value.downcast_ref().unwrap_or(self.access),
            "OperatorName" => self.operator = owned().and_then(|v| String::try_from(v).ok()).unwrap_or_default(),
            "RegistrationState" => self.registration = value.downcast_ref().unwrap_or(self.registration),
            "EmergencyOnly" => self.emergency_only = value.downcast_ref().unwrap_or(self.emergency_only),
            "SupportedModes" => self.supported = owned().and_then(|v| Vec::try_from(v).ok()).unwrap_or_default(),
            "CurrentModes" => self.current = owned().and_then(|v| <(u32, u32)>::try_from(v).ok()).map_or(self.current, |m| m.0 & !CIRCUIT_SWITCHED),
            _ => {}
        }
    }

    // Each allowed mask once, widest first.
    fn modes(&self) -> Vec<u32> {
        let mut modes: Vec<u32> = self.supported.iter().map(|&(allowed, _)| allowed & !CIRCUIT_SWITCHED).collect();
        modes.sort_unstable_by(|a, b| b.cmp(a));
        modes.dedup();
        modes
    }

    // The preferred mode for `allowed`: its fastest, if the modem offers it.
    fn preferred(&self, allowed: u32) -> Option<u32> {
        let choices: Vec<u32> = self.supported.iter().filter(|(a, _)| a & !CIRCUIT_SWITCHED == allowed).map(|&(_, p)| p).collect();
        let fastest = if allowed == 0 { 0 } else { 1 << allowed.ilog2() };
        choices.contains(&fastest).then_some(fastest).or_else(|| choices.first().copied())
    }

    fn view(&self, daemon: bool) -> View {
        // ModemManager's states: 3 enabled and up; 10 connecting, 11 connected.
        // 3GPP registration: 1 home, 5 roaming. Signal.Rssi, when something
        // set it up, beats the coarser SignalQuality.
        let strength = if self.rssi == 0.0 {
            i32::try_from(self.quality.min(100)).unwrap_or(0)
        } else {
            #[allow(clippy::cast_possible_truncation, reason = "clamped to 0..=100")]
            let s = ((self.rssi + 100.0) * 2.0).clamp(0.0, 100.0) as i32;
            s
        };
        View {
            daemon,
            modem: self.path.is_some(),
            enabled: self.state >= 3,
            data: self.state >= 10,
            strength,
            registered: matches!(self.registration, 1 | 5),
            roaming: self.registration == 5,
            sim: self.sim.is_some(),
            emergency_only: self.emergency_only,
            operator: self.operator.clone(),
            network_type: network_type(self.access),
            emergency_numbers: self.emergency_numbers.clone(),
            modes: self.modes(),
            allowed: self.current,
        }
    }
}

fn network_type(access: u32) -> &'static str {
    [(0x8000, "5G"), (0x4000, "LTE"), (0x0600, "HSPA+"), (0x0100, "HSPA"), (0x0020, "UMTS"), (0x0010, "EDGE"), (0x0002, "GPRS"), (0x0001, "GSM")]
        .iter()
        .find(|(bit, _)| access & bit != 0)
        .map_or("Unknown", |&(_, name)| name)
}

/// An emergency alert, as the overlay reads it.
struct Broadcast {
    path: String,
    text: String,
    channel: u32,
    fields: [(&'static str, u32); 4],
    received_ms: i64,
}

impl Broadcast {
    fn category(&self) -> &'static str {
        match self.channel {
            4370 => "presidential",
            4371..=4378 | 4380..=4395 => "imminent",
            4379 => "amber",
            4396 => "test",
            4352..=4356 => "ETWS",
            _ => "other",
        }
    }

    fn to_map(&self) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        let category = self.category();
        map.insert(QString::from("path"), QVariant::from(&QString::from(self.path.as_str())));
        map.insert(QString::from("text"), QVariant::from(&QString::from(self.text.as_str())));
        map.insert(QString::from("channelId"), QVariant::from(&self.channel));
        for (key, value) in self.fields {
            map.insert(QString::from(key), QVariant::from(&value));
        }
        map.insert(QString::from("category"), QVariant::from(&QString::from(category)));
        map.insert(QString::from("nonDismissable"), QVariant::from(&matches!(category, "presidential" | "ETWS")));
        map.insert(QString::from("receivedMsecsSinceEpoch"), QVariant::from(&self.received_ms));
        map
    }
}

const MM: &str = "org.freedesktop.ModemManager1";
const MODEM: &str = "org.freedesktop.ModemManager1.Modem";
const CELL_BROADCAST: &str = "org.freedesktop.ModemManager1.Modem.CellBroadcast";

#[zbus::proxy(interface = "org.freedesktop.ModemManager1.Modem", default_service = "org.freedesktop.ModemManager1")]
trait Modem {
    fn enable(&self, enable: bool) -> zbus::Result<()>;
    fn set_current_modes(&self, modes: &(u32, u32)) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.freedesktop.ModemManager1.Modem.Simple", default_service = "org.freedesktop.ModemManager1")]
trait Simple {
    fn connect(&self, properties: HashMap<&str, Value<'_>>) -> zbus::Result<OwnedObjectPath>;
    fn disconnect(&self, bearer: &zbus::zvariant::ObjectPath<'_>) -> zbus::Result<()>;
}

type Qt = cxx_qt::CxxQtThread<ModemManagerCpp>;

enum Event {
    Command(Command),
    Closed,
    Objects,
    Changed(HashMap<String, OwnedValue>),
    BroadcastAdded(OwnedObjectPath),
    BroadcastGone(OwnedObjectPath),
}

async fn run(qt: Qt, commands: Receiver<Command>) {
    let Ok(bus) = io::system_bus().await else { return };
    let Ok(manager) = ObjectManagerProxy::builder(&bus).destination(MM).and_then(|b| b.path("/org/freedesktop/ModemManager1")) else { return };
    let Ok(manager) = manager.build().await else { return };
    // The modem coming or going, or ModemManager starting: look again.
    let mut objects = stream::empty().boxed();
    if let (Ok(added), Ok(removed)) = (manager.receive_interfaces_added().await, manager.receive_interfaces_removed().await) {
        objects = added.map(|_| Event::Objects).or(removed.map(|_| Event::Objects)).boxed();
    }
    if let Ok(dbus) = DBusProxy::new(&bus).await {
        if let Ok(owners) = dbus.receive_name_owner_changed_with_args(&[(0, MM)]).await {
            objects = objects.or(owners.map(|_| Event::Objects)).boxed();
        }
    }
    let shared = commands.map(Event::Command).chain(stream::once(Event::Closed)).or(objects);
    let mut shared = std::pin::pin!(shared);
    let mut state = Snapshot::default();
    let mut modem_events: Option<stream::Boxed<Event>> = None;
    let mut daemon = discover(&bus, &manager, &qt, &mut state, &mut modem_events).await;
    loop {
        let event = match &mut modem_events {
            Some(own) => future::or(shared.next(), own.next()).await,
            None => shared.next().await,
        };
        match event {
            None | Some(Event::Closed) => return,
            Some(Event::Command(command)) => act(&bus, &state, command).await,
            Some(Event::Objects) => daemon = discover(&bus, &manager, &qt, &mut state, &mut modem_events).await,
            Some(Event::Changed(changed)) => {
                let sim = state.sim.clone();
                for (name, value) in &changed {
                    state.set(name, value);
                }
                if state.sim != sim {
                    state.emergency_numbers = emergency_numbers(&bus, state.sim.as_ref()).await;
                }
            }
            Some(Event::BroadcastAdded(path)) => load_broadcast(&bus, &qt, path).await,
            Some(Event::BroadcastGone(path)) => {
                qt.queue(move |obj| obj.broadcast_gone(path.as_str())).ok();
            }
        }
        let view = state.view(daemon);
        qt.queue(move |obj| obj.apply(&view)).ok();
    }
}

/// Finds the modem in `ModemManager`'s objects, taking every interface's
/// properties from the same reply; whether `ModemManager` answered.
async fn discover(bus: &zbus::Connection, manager: &ObjectManagerProxy<'_>, qt: &Qt, state: &mut Snapshot, events: &mut Option<stream::Boxed<Event>>) -> bool {
    let Ok(objects) = manager.get_managed_objects().await else {
        *state = Snapshot::default();
        *events = None;
        return false;
    };
    let found = objects.into_iter().find(|(_, interfaces)| interfaces.keys().any(|i| i.as_str() == MODEM));
    let Some((path, interfaces)) = found else {
        *state = Snapshot::default();
        *events = None;
        return true;
    };
    if state.path.as_ref() == Some(&path) {
        return true;
    }
    *state = Snapshot { path: Some(path.clone()), ..Snapshot::default() };
    for properties in interfaces.values() {
        for (name, value) in properties {
            state.set(name, value);
        }
    }
    state.emergency_numbers = emergency_numbers(bus, state.sim.as_ref()).await;
    let broadcasts = interfaces
        .iter()
        .find(|(i, _)| i.as_str() == CELL_BROADCAST)
        .and_then(|(_, p)| p.get("CellBroadcasts"))
        .and_then(|v| Vec::<OwnedObjectPath>::try_from(v.try_clone().ok()?).ok())
        .unwrap_or_default();
    for broadcast in broadcasts {
        load_broadcast(bus, qt, broadcast).await;
    }
    *events = Some(modem_events(bus, path).await);
    true
}

// The modem's property changes and its cell broadcasts arriving and going.
async fn modem_events(bus: &zbus::Connection, path: OwnedObjectPath) -> stream::Boxed<Event> {
    let mut events = stream::empty().boxed();
    if let Ok(props) = PropertiesProxy::builder(bus).destination(MM).and_then(|b| b.path(path.clone())) {
        if let Ok(props) = props.cache_properties(zbus::proxy::CacheProperties::No).build().await {
            if let Ok(changes) = props.receive_properties_changed().await {
                events = changes
                    .filter_map(|signal| {
                        let args = signal.args().ok()?;
                        let changed = args.changed_properties().iter().filter_map(|(k, v)| Some(((*k).to_owned(), v.try_to_owned().ok()?))).collect();
                        Some(Event::Changed(changed))
                    })
                    .boxed();
            }
        }
    }
    let rule = MatchRule::builder()
        .msg_type(MessageType::Signal)
        .sender(MM)
        .and_then(|b| b.interface(CELL_BROADCAST))
        .and_then(|b| b.path(path))
        .map(zbus::match_rule::Builder::build);
    if let Ok(rule) = rule {
        if let Ok(signals) = MessageStream::for_match_rule(rule, bus, Some(16)).await {
            let broadcasts = signals.filter_map(|m| {
                let m = m.ok()?;
                match m.header().member()?.as_str() {
                    "Added" => {
                        let (path, received): (OwnedObjectPath, bool) = m.body().deserialize().ok()?;
                        received.then_some(Event::BroadcastAdded(path))
                    }
                    "Deleted" => Some(Event::BroadcastGone(m.body().deserialize().ok()?)),
                    _ => None,
                }
            });
            events = events.or(broadcasts).boxed();
        }
    }
    events
}

async fn properties(bus: &zbus::Connection, path: &OwnedObjectPath, interface: &'static str) -> HashMap<String, OwnedValue> {
    let props = async {
        let props = PropertiesProxy::builder(bus).destination(MM).ok()?.path(path.clone()).ok()?;
        let props = props.cache_properties(zbus::proxy::CacheProperties::No).build().await.ok()?;
        props.get_all(zbus::names::InterfaceName::try_from(interface).ok()?).await.ok()
    };
    props.await.unwrap_or_default()
}

// The SIM's EF_ECC list: readable while it is PIN-locked.
async fn emergency_numbers(bus: &zbus::Connection, sim: Option<&OwnedObjectPath>) -> Vec<String> {
    let Some(sim) = sim else { return Vec::new() };
    properties(bus, sim, "org.freedesktop.ModemManager1.Sim")
        .await
        .remove("EmergencyNumbers")
        .and_then(|v| Vec::try_from(v).ok())
        .unwrap_or_default()
}

async fn load_broadcast(bus: &zbus::Connection, qt: &Qt, path: OwnedObjectPath) {
    let props = properties(bus, &path, "org.freedesktop.ModemManager1.CellBroadcast").await;
    let number = |k: &str| props.get(k).and_then(|v| u32::try_from(v).ok()).unwrap_or(0);
    let broadcast = Broadcast {
        text: props.get("Text").and_then(|v| String::try_from(v.try_clone().ok()?).ok()).unwrap_or_default(),
        channel: number("ChannelId"),
        fields: [("messageCode", number("MessageCode")), ("updateNumber", number("UpdateNumber")), ("serial", number("Serial")), ("state", number("Snapshot"))],
        received_ms: SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(0)),
        path: path.to_string(),
    };
    qt.queue(move |obj| obj.broadcast(broadcast)).ok();
}

async fn act(bus: &zbus::Connection, state: &Snapshot, command: Command) {
    let Some(path) = state.path.clone() else { return };
    let result = match command {
        Command::Enable(on) => match ModemProxy::builder(bus).path(path) {
            Ok(b) => match b.build().await {
                Ok(modem) => modem.enable(on).await,
                Err(e) => Err(e),
            },
            Err(e) => Err(e),
        },
        Command::Modes(allowed) => match (state.preferred(allowed), ModemProxy::builder(bus).path(path)) {
            (Some(preferred), Ok(b)) => match b.build().await {
                Ok(modem) => modem.set_current_modes(&(allowed, preferred)).await,
                Err(e) => Err(e),
            },
            (None, _) => Ok(()),
            (_, Err(e)) => Err(e),
        },
        // Dialling a bearer takes seconds; the I/O thread waits, not the GUI.
        Command::Data(on, roaming) => match SimpleProxy::builder(bus).path(path) {
            Ok(b) => match b.build().await {
                Ok(simple) if on => simple.connect(HashMap::from([("apn", Value::from("")), ("allow-roaming", Value::from(roaming))])).await.map(drop),
                Ok(simple) => simple.disconnect(&zbus::zvariant::ObjectPath::from_static_str_unchecked("/")).await,
                Err(e) => Err(e),
            },
            Err(e) => Err(e),
        },
    };
    if let Err(e) = result {
        log::warn("modem", e);
    }
}

#[cfg(test)]
mod tests {
    use super::{network_type, Snapshot};

    #[test]
    fn the_fastest_access_technology_names_the_network() {
        assert_eq!(network_type(0x4000 | 0x0020), "LTE");
        assert_eq!(network_type(0x0400), "HSPA+");
        assert_eq!(network_type(0), "Unknown");
    }

    #[test]
    fn modes_are_offered_widest_first_with_their_fastest_preferred() {
        // 2G|3G|4G with 4G or 3G preferred, 2G|3G, and 4G only; CS bit set.
        let state = Snapshot { supported: vec![(0b1111, 8), (0b1111, 4), (0b0111, 4), (0b1001, 8)], ..Snapshot::default() };
        assert_eq!(state.modes(), [0b1110, 0b1000, 0b0110]);
        assert_eq!(state.preferred(0b1110), Some(8));
        assert_eq!(state.preferred(0b0110), Some(4));
        assert_eq!(state.preferred(0b0001), None);
    }

    #[test]
    fn rssi_wins_over_signal_quality() {
        let mut state = Snapshot { quality: 40, ..Snapshot::default() };
        assert_eq!(state.view(true).strength, 40);
        state.rssi = -70.0;
        assert_eq!(state.view(true).strength, 60);
    }
}
