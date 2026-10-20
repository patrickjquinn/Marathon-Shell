//! `Bluetooth`: the adapter, its devices and the pairing agent. `BlueZ` is
//! only read and driven from one actor on the I/O thread, its objects cached
//! from `GetManagedObjects` and kept by their signals.

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::{stream, StreamExt};
use zbus::fdo::{DBusProxy, ObjectManagerProxy};
use zbus::message::Type as MessageType;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::{MatchRule, MessageStream};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, enabled, READ, WRITE = set_enabled, NOTIFY)]
        #[qproperty(bool, scanning, READ, NOTIFY)]
        #[qproperty(bool, discoverable, READ, WRITE = set_discoverable, NOTIFY)]
        #[qproperty(QString, adapter_name, cxx_name = "adapterName", READ, NOTIFY)]
        /// Each device as a map: address, name, alias, paired, connected,
        /// trusted, rssi and icon.
        #[qproperty(QList_QVariant, devices, READ, NOTIFY)]
        #[qproperty(QList_QVariant, paired_devices, cxx_name = "pairedDevices", READ, NOTIFY)]
        type Bluetooth = super::BluetoothRust;

        #[cxx_name = "setEnabled"]
        fn set_enabled(self: Pin<&mut Bluetooth>, enabled: bool);
        #[cxx_name = "setDiscoverable"]
        fn set_discoverable(self: Pin<&mut Bluetooth>, discoverable: bool);

        #[qsignal]
        #[cxx_name = "pairingFailed"]
        fn pairing_failed(self: Pin<&mut Self>, address: &QString, error: &QString);
        #[qsignal]
        #[cxx_name = "pairingSucceeded"]
        fn pairing_succeeded(self: Pin<&mut Self>, address: &QString);
        #[qsignal]
        #[cxx_name = "pinRequested"]
        fn pin_requested(self: Pin<&mut Self>, address: &QString, device_name: &QString);
        #[qsignal]
        #[cxx_name = "passkeyRequested"]
        fn passkey_requested(self: Pin<&mut Self>, address: &QString, device_name: &QString);
        #[qsignal]
        #[cxx_name = "passkeyConfirmation"]
        fn passkey_confirmation(self: Pin<&mut Self>, address: &QString, device_name: &QString, passkey: u32);

        /// The name other devices see.
        #[qinvokable]
        #[cxx_name = "setAdapterAlias"]
        fn set_adapter_alias(self: &Bluetooth, alias: &QString);
        /// Discovery, which stops by itself after 30 s.
        #[qinvokable]
        #[cxx_name = "startScan"]
        fn start_scan(self: &Bluetooth);
        #[qinvokable]
        #[cxx_name = "stopScan"]
        fn stop_scan(self: &Bluetooth);
        /// Pairs with the device or, with a `pin`, answers its PIN or
        /// passkey request.
        #[qinvokable]
        #[cxx_name = "pairDevice"]
        fn pair_device(self: &Bluetooth, address: &QString, pin: &QString);
        #[qinvokable]
        #[cxx_name = "unpairDevice"]
        fn unpair_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "connectDevice"]
        fn connect_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "disconnectDevice"]
        fn disconnect_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "removeDevice"]
        fn remove_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "cancelPairing"]
        fn cancel_pairing(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "confirmPairing"]
        fn confirm_pairing(self: &Bluetooth, address: &QString, confirmed: bool);
    }

    impl cxx_qt::Threading for Bluetooth {}
    impl cxx_qt::Initialize for Bluetooth {}
}

use qobject::Bluetooth;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct BluetoothRust {
    available: bool,
    enabled: bool,
    scanning: bool,
    discoverable: bool,
    adapter_name: QString,
    devices: QList<QVariant>,
    paired_devices: QList<QVariant>,
    known: Vec<Device>,
    actor: Option<Sender<Command>>,
    answers: Option<Sender<Answer>>,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct Device {
    path: String,
    address: String,
    name: String,
    alias: String,
    paired: bool,
    connected: bool,
    trusted: bool,
    rssi: i16,
    icon: &'static str,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct Adapter {
    powered: bool,
    discovering: bool,
    discoverable: bool,
    alias: String,
}

enum Command {
    Powered(bool),
    Discoverable(bool),
    Alias(String),
    Scan(bool),
    Pair { path: String, address: String },
    Call { path: String, method: &'static str },
    Remove(String),
}

/// What the person answered to the agent.
enum Answer {
    Pin(String),
    Confirm(bool),
    Cancel,
}

#[derive(Clone, Copy)]
enum Ask {
    Pin,
    Passkey,
    Confirm(u32),
}

impl cxx_qt::Initialize for Bluetooth {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(32);
        let (answer, answers) = async_channel::bounded(4);
        io::spawn(run(self.qt_thread(), rx, answer.clone(), answers));
        let mut rust = self.as_mut().rust_mut();
        rust.actor = Some(tx);
        rust.answers = Some(answer);
    }
}

impl Bluetooth {
    fn send(&self, command: Command) {
        if self.actor.as_ref().is_none_or(|a| a.try_send(command).is_err()) {
            log::warn("bluetooth", "no Bluetooth backend");
        }
    }

    fn answer(&self, answer: Answer) {
        if let Some(answers) = &self.answers {
            answers.try_send(answer).ok();
        }
    }

    fn path_of(&self, address: &QString) -> Option<String> {
        let address = address.to_string();
        self.known.iter().find(|d| d.address == address).map(|d| d.path.clone())
    }

    fn call(&self, address: &QString, method: &'static str) {
        if let Some(path) = self.path_of(address) {
            self.send(Command::Call { path, method });
        }
    }

    fn set_enabled(self: Pin<&mut Self>, enabled: bool) {
        if self.available && self.enabled != enabled {
            self.send(Command::Powered(enabled));
        }
    }

    fn set_discoverable(self: Pin<&mut Self>, discoverable: bool) {
        if self.available && self.discoverable != discoverable {
            self.send(Command::Discoverable(discoverable));
        }
    }

    fn set_adapter_alias(&self, alias: &QString) {
        if self.available && !alias.is_empty() && *alias != self.adapter_name {
            self.send(Command::Alias(alias.to_string()));
        }
    }

    fn start_scan(&self) {
        self.send(Command::Scan(true));
    }

    fn stop_scan(&self) {
        self.send(Command::Scan(false));
    }

    fn pair_device(&self, address: &QString, pin: &QString) {
        if !pin.is_empty() {
            self.answer(Answer::Pin(pin.to_string()));
        } else if let Some(path) = self.path_of(address) {
            self.send(Command::Pair { path, address: address.to_string() });
        }
    }

    fn unpair_device(&self, address: &QString) {
        self.remove_device(address);
    }

    fn connect_device(&self, address: &QString) {
        self.call(address, "Connect");
    }

    fn disconnect_device(&self, address: &QString) {
        self.call(address, "Disconnect");
    }

    fn remove_device(&self, address: &QString) {
        if let Some(path) = self.path_of(address) {
            self.send(Command::Remove(path));
        }
    }

    fn cancel_pairing(&self, address: &QString) {
        self.call(address, "CancelPairing");
    }

    fn confirm_pairing(&self, _address: &QString, confirmed: bool) {
        self.answer(Answer::Confirm(confirmed));
    }

    fn apply_adapter(mut self: Pin<&mut Self>, available: bool, adapter: &Adapter) {
        set!(self, available, available_changed, available);
        set!(self, enabled, enabled_changed, adapter.powered);
        set!(self, scanning, scanning_changed, adapter.discovering);
        set!(self, discoverable, discoverable_changed, adapter.discoverable);
        set!(self, adapter_name, adapter_name_changed, QString::from(adapter.alias.as_str()));
    }

    fn apply_devices(mut self: Pin<&mut Self>, devices: Vec<Device>) {
        let paired = |list: &[Device]| list.iter().filter(|d| d.paired).cloned().collect::<Vec<_>>();
        let paired_changed = paired(&devices) != paired(&self.known);
        let mut rust = self.as_mut().rust_mut();
        rust.devices = to_list(devices.iter());
        rust.paired_devices = to_list(devices.iter().filter(|d| d.paired));
        rust.known = devices;
        self.as_mut().devices_changed();
        if paired_changed {
            self.paired_devices_changed();
        }
    }

    fn agent_request(mut self: Pin<&mut Self>, ask: Ask, path: &str) {
        let device = self.known.iter().find(|d| d.path == path);
        let name = QString::from(device.map_or("Unknown Device", Device::shown_name));
        let address = QString::from(device.map_or_else(|| address_of(path), |d| d.address.clone()).as_str());
        match ask {
            Ask::Pin => self.as_mut().pin_requested(&address, &name),
            Ask::Passkey => self.as_mut().passkey_requested(&address, &name),
            Ask::Confirm(passkey) => self.as_mut().passkey_confirmation(&address, &name, passkey),
        }
    }
}

impl Device {
    fn set(&mut self, key: &str, value: &Value<'_>) {
        let text = || value.downcast_ref::<&str>().map(str::to_owned).unwrap_or_default();
        let flag = || value.downcast_ref::<bool>().unwrap_or(false);
        match key {
            "Address" => self.address = text(),
            "Name" => self.name = text(),
            "Alias" => self.alias = text(),
            "Paired" => self.paired = flag(),
            "Connected" => self.connected = flag(),
            "Trusted" => self.trusted = flag(),
            "RSSI" => self.rssi = value.downcast_ref::<i16>().unwrap_or(0),
            "Icon" => self.icon = icon(&text()),
            _ => {}
        }
    }

    fn shown_name(&self) -> &str {
        if self.alias.is_empty() {
            &self.name
        } else {
            &self.alias
        }
    }

    fn to_map(&self) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        let mut text = |key: &str, value: &str| map.insert(QString::from(key), QVariant::from(&QString::from(value)));
        text("address", &self.address);
        text("name", &self.name);
        text("alias", &self.alias);
        text("icon", self.icon);
        map.insert(QString::from("paired"), QVariant::from(&self.paired));
        map.insert(QString::from("connected"), QVariant::from(&self.connected));
        map.insert(QString::from("trusted"), QVariant::from(&self.trusted));
        map.insert(QString::from("rssi"), QVariant::from(&i32::from(self.rssi)));
        map
    }
}

impl Adapter {
    fn set(&mut self, key: &str, value: &Value<'_>) {
        match key {
            "Powered" => self.powered = value.downcast_ref().unwrap_or(false),
            "Discovering" => self.discovering = value.downcast_ref().unwrap_or(false),
            "Discoverable" => self.discoverable = value.downcast_ref().unwrap_or(false),
            "Alias" => self.alias = value.downcast_ref::<&str>().map(str::to_owned).unwrap_or_default(),
            _ => {}
        }
    }
}

fn to_list<'a>(devices: impl Iterator<Item = &'a Device>) -> QList<QVariant> {
    let mut list = QList::<QVariant>::default();
    for d in devices {
        list.append(QVariant::from(&d.to_map()));
    }
    list
}

/// `BlueZ`'s icon name as a Lucide one.
fn icon(raw: &str) -> &'static str {
    let any = |names: &[&str]| names.iter().any(|n| raw.contains(n));
    if any(&["audio-card", "speaker"]) {
        "volume-2"
    } else if any(&["headphone", "headset"]) {
        "music"
    } else if any(&["computer", "laptop", "monitor"]) {
        "monitor"
    } else if any(&["phone"]) {
        "smartphone"
    } else if any(&["keyboard"]) {
        "keyboard"
    } else if any(&["watch"]) {
        "clock"
    } else {
        "bluetooth"
    }
}

/// `/org/bluez/hci0/dev_AA_BB_…` as `AA:BB:…`.
fn address_of(path: &str) -> String {
    path.rsplit('/').next().and_then(|s| s.strip_prefix("dev_")).map(|s| s.replace('_', ":")).unwrap_or_default()
}

const BLUEZ: &str = "org.bluez";
const ADAPTER: &str = "org.bluez.Adapter1";
const DEVICE: &str = "org.bluez.Device1";
const AGENT: &str = "/org/marathon/bluetooth/agent";

#[zbus::proxy(interface = "org.bluez.Adapter1", default_service = "org.bluez")]
trait Adapter1 {
    fn start_discovery(&self) -> zbus::Result<()>;
    fn stop_discovery(&self) -> zbus::Result<()>;
    fn remove_device(&self, device: &ObjectPath<'_>) -> zbus::Result<()>;
    #[zbus(property)]
    fn powered(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn set_powered(&self, powered: bool) -> zbus::Result<()>;
    #[zbus(property)]
    fn discoverable(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn set_discoverable(&self, discoverable: bool) -> zbus::Result<()>;
    #[zbus(property)]
    fn alias(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn set_alias(&self, alias: &str) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.bluez.AgentManager1", default_service = "org.bluez", default_path = "/org/bluez")]
trait AgentManager1 {
    fn register_agent(&self, agent: &ObjectPath<'_>, capability: &str) -> zbus::Result<()>;
    fn request_default_agent(&self, agent: &ObjectPath<'_>) -> zbus::Result<()>;
}

type Qt = cxx_qt::CxxQtThread<Bluetooth>;
type Properties = HashMap<String, OwnedValue>;

enum Event {
    Command(Command),
    Closed,
    Changed { path: OwnedObjectPath, interface: String, changed: Properties, invalidated: Vec<String> },
    Added { path: OwnedObjectPath, interfaces: HashMap<String, Properties> },
    Removed { path: OwnedObjectPath, interfaces: Vec<String> },
    /// bluetoothd started or stopped.
    Restarted,
    ScanTimeout(u64),
}

struct Actor {
    qt: Qt,
    bus: zbus::Connection,
    adapter: Option<OwnedObjectPath>,
    state: Adapter,
    devices: Vec<Device>,
    scans: u64,
    timeouts: Sender<u64>,
}

async fn run(qt: Qt, commands: Receiver<Command>, answer: Sender<Answer>, answers: Receiver<Answer>) {
    let bus = match io::system_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("bluetooth", format_args!("no system bus: {e}")),
    };
    let agent = Agent { qt: qt.clone(), answers, cancel: answer };
    if let Err(e) = bus.object_server().at(AGENT, agent).await {
        log::warn("bluetooth", format_args!("no pairing agent: {e}"));
    }
    let (timeouts, timed_out) = async_channel::bounded(4);
    let mut actor = Actor { qt, bus, adapter: None, state: Adapter::default(), devices: Vec::new(), scans: 0, timeouts };
    let events = commands
        .map(Event::Command)
        .chain(stream::once(Event::Closed))
        .or(actor.signals().await)
        .or(timed_out.map(Event::ScanTimeout));
    let mut events = std::pin::pin!(events);
    actor.load().await;
    while let Some(event) = events.next().await {
        match event {
            Event::Command(command) => actor.handle(command).await,
            Event::Closed => break,
            Event::Changed { path, interface, changed, invalidated } => {
                let reset = Value::Bool(false);
                let values = changed.iter().map(|(k, v)| (k.as_str(), &**v)).chain(invalidated.iter().map(|k| (k.as_str(), &reset)));
                if interface == ADAPTER && actor.adapter.as_ref() == Some(&path) {
                    values.for_each(|(k, v)| actor.state.set(k, v));
                    actor.publish_adapter();
                } else if let (DEVICE, Some(device)) = (interface.as_str(), actor.devices.iter_mut().find(|d| d.path == path.as_str())) {
                    values.for_each(|(k, v)| device.set(k, v));
                    actor.publish_devices();
                }
            }
            Event::Added { path, interfaces } => {
                if interfaces.contains_key(ADAPTER) && actor.adapter.is_none() {
                    actor.load().await;
                } else if let Some(props) = interfaces.get(DEVICE) {
                    actor.add(&path, props);
                    actor.publish_devices();
                }
            }
            Event::Removed { path, interfaces } => {
                if interfaces.iter().any(|i| i == ADAPTER) && actor.adapter.as_ref() == Some(&path) {
                    actor.load().await;
                } else if interfaces.iter().any(|i| i == DEVICE) {
                    actor.devices.retain(|d| d.path != path.as_str());
                    actor.publish_devices();
                }
            }
            Event::Restarted => actor.load().await,
            Event::ScanTimeout(scan) => {
                if scan == actor.scans {
                    actor.handle(Command::Scan(false)).await;
                }
            }
        }
    }
}

impl Actor {
    fn publish_adapter(&self) {
        let (available, state) = (self.adapter.is_some(), self.state.clone());
        self.qt.queue(move |obj| obj.apply_adapter(available, &state)).ok();
    }

    fn publish_devices(&self) {
        let devices = self.devices.clone();
        self.qt.queue(move |obj| obj.apply_devices(devices)).ok();
    }

    fn add(&mut self, path: &OwnedObjectPath, props: &Properties) {
        if self.adapter.as_ref().is_none_or(|a| !path.as_str().starts_with(a.as_str())) || self.devices.iter().any(|d| d.path == path.as_str()) {
            return;
        }
        let mut device = Device { path: path.to_string(), icon: icon(""), ..Device::default() };
        for (key, value) in props {
            device.set(key, value);
        }
        self.devices.push(device);
    }

    /// Everything `BlueZ` has, again: at start, and when bluetoothd or its
    /// adapter comes or goes.
    async fn load(&mut self) {
        self.adapter = None;
        self.state = Adapter::default();
        self.devices.clear();
        let objects = match ObjectManagerProxy::builder(&self.bus).destination(BLUEZ).and_then(|b| b.path("/")) {
            Ok(b) => match b.build().await {
                Ok(manager) => manager.get_managed_objects().await,
                Err(e) => Err(e.into()),
            },
            Err(e) => Err(e.into()),
        };
        let objects = objects.unwrap_or_default();
        let adapter = objects.iter().find_map(|(path, ifaces)| Some((path, ifaces.iter().find(|(i, _)| i.as_str() == ADAPTER)?.1)));
        if let Some((path, props)) = adapter {
            self.adapter = Some(path.clone());
            for (key, value) in props {
                self.state.set(key, value);
            }
        }
        for (path, ifaces) in &objects {
            if let Some((_, props)) = ifaces.iter().find(|(i, _)| i.as_str() == DEVICE) {
                self.add(path, props);
            }
        }
        self.publish_adapter();
        self.publish_devices();
        if self.adapter.is_some() {
            self.register_agent().await;
        }
    }

    async fn register_agent(&self) {
        let registered = async {
            let manager = AgentManager1Proxy::new(&self.bus).await?;
            let path = ObjectPath::from_static_str_unchecked(AGENT);
            match manager.register_agent(&path, "KeyboardDisplay").await {
                Err(zbus::Error::MethodError(name, _, _)) if name.as_str() == "org.bluez.Error.AlreadyExists" => {}
                other => other?,
            }
            manager.request_default_agent(&path).await
        };
        if let Err(e) = registered.await {
            log::warn("bluetooth", format_args!("pairing agent not registered: {e}"));
        }
    }

    async fn adapter_proxy(&self) -> Option<Adapter1Proxy<'static>> {
        let path = self.adapter.clone()?;
        Adapter1Proxy::builder(&self.bus).path(path).ok()?.cache_properties(zbus::proxy::CacheProperties::No).build().await.ok()
    }

    async fn handle(&mut self, command: Command) {
        let Some(adapter) = self.adapter_proxy().await else { return };
        let result = match command {
            Command::Powered(on) => {
                if on {
                    crate::network::set_rfkill(&["bluetooth"], false);
                }
                adapter.set_powered(on).await
            }
            Command::Discoverable(on) => adapter.set_discoverable(on).await,
            Command::Alias(alias) => adapter.set_alias(&alias).await,
            Command::Scan(on) => {
                self.scans += 1;
                if on {
                    let (scan, timeouts) = (self.scans, self.timeouts.clone());
                    io::spawn(async move {
                        Timer::after(Duration::from_secs(30)).await;
                        timeouts.send(scan).await.ok();
                    });
                    adapter.start_discovery().await
                } else {
                    adapter.stop_discovery().await
                }
            }
            Command::Remove(path) => match ObjectPath::try_from(path.as_str()) {
                Ok(path) => adapter.remove_device(&path).await,
                Err(e) => Err(e.into()),
            },
            // These wait on the device, and pairing on the person.
            Command::Pair { path, address } => {
                let (bus, qt) = (self.bus.clone(), self.qt.clone());
                io::spawn(async move {
                    let result = device_call(&bus, &path, "Pair").await;
                    qt.queue(move |mut obj| {
                        let address = QString::from(address.as_str());
                        match result {
                            Ok(()) => obj.as_mut().pairing_succeeded(&address),
                            Err(e) => obj.as_mut().pairing_failed(&address, &QString::from(pairing_error(&e).as_str())),
                        }
                    })
                    .ok();
                });
                Ok(())
            }
            Command::Call { path, method } => {
                let bus = self.bus.clone();
                io::spawn(async move {
                    if let Err(e) = device_call(&bus, &path, method).await {
                        log::warn("bluetooth", format_args!("{method} {path}: {e}"));
                    }
                });
                Ok(())
            }
        };
        if let Err(e) = result {
            log::warn("bluetooth", e);
        }
    }

    async fn signals(&self) -> stream::Boxed<Event> {
        let rule = |interface: &'static str, member: &'static str| {
            MatchRule::builder()
                .msg_type(MessageType::Signal)
                .sender(BLUEZ)
                .and_then(|b| b.interface(interface))
                .and_then(|b| b.member(member))
                .map(zbus::match_rule::Builder::build)
        };
        let stream = |rule: zbus::Result<MatchRule<'static>>| async {
            MessageStream::for_match_rule(rule.ok()?, &self.bus, Some(64)).await.ok()
        };
        let mut merged = stream::empty().boxed();
        if let Some(s) = stream(rule("org.freedesktop.DBus.Properties", "PropertiesChanged")).await {
            merged = merged
                .or(s.filter_map(|m| {
                    let m = m.ok()?;
                    let path = OwnedObjectPath::from(m.header().path()?.clone());
                    let (interface, changed, invalidated) = m.body().deserialize().ok()?;
                    Some(Event::Changed { path, interface, changed, invalidated })
                }))
                .boxed();
        }
        if let Some(s) = stream(rule("org.freedesktop.DBus.ObjectManager", "InterfacesAdded")).await {
            merged = merged
                .or(s.filter_map(|m| {
                    let (path, interfaces) = m.ok()?.body().deserialize().ok()?;
                    Some(Event::Added { path, interfaces })
                }))
                .boxed();
        }
        if let Some(s) = stream(rule("org.freedesktop.DBus.ObjectManager", "InterfacesRemoved")).await {
            merged = merged
                .or(s.filter_map(|m| {
                    let (path, interfaces) = m.ok()?.body().deserialize().ok()?;
                    Some(Event::Removed { path, interfaces })
                }))
                .boxed();
        }
        if let Ok(dbus) = DBusProxy::new(&self.bus).await {
            if let Ok(owners) = dbus.receive_name_owner_changed_with_args(&[(0, BLUEZ)]).await {
                merged = merged.or(owners.map(|_| Event::Restarted)).boxed();
            }
        }
        merged
    }
}

async fn device_call(bus: &zbus::Connection, path: &str, method: &str) -> zbus::Result<()> {
    bus.call_method(Some(BLUEZ), path, Some(DEVICE), method, &()).await.map(|_| ())
}

fn pairing_error(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, message, _) => message.clone().unwrap_or_else(|| name.to_string()),
        other => other.to_string(),
    }
}

#[allow(clippy::unused_self, clippy::used_underscore_binding, reason = "Agent1's methods, most answered as they come")]
mod agent {
    use async_channel::{Receiver, Sender};
    use zbus::zvariant::ObjectPath;

    use super::{Answer, Ask, Qt};

    /// `BlueZ`'s agent: each request goes to the person, and waits for their
    /// answer or `BlueZ`'s `Cancel`.
    pub(super) struct Agent {
        pub(super) qt: Qt,
        pub(super) answers: Receiver<Answer>,
        pub(super) cancel: Sender<Answer>,
    }

    #[derive(Debug, zbus::DBusError)]
    #[zbus(prefix = "org.bluez.Error")]
    enum AgentError {
        #[zbus(error)]
        ZBus(zbus::Error),
        Rejected(String),
    }

    fn rejected() -> AgentError {
        AgentError::Rejected("Rejected by the user".to_owned())
    }

    impl Agent {
        async fn ask(&self, ask: Ask, device: &ObjectPath<'_>) -> Answer {
            while self.answers.try_recv().is_ok() {}
            let path = device.to_string();
            self.qt.queue(move |obj| obj.agent_request(ask, &path)).ok();
            self.answers.recv().await.unwrap_or(Answer::Cancel)
        }
    }

    #[zbus::interface(name = "org.bluez.Agent1")]
    impl Agent {
        fn release(&self) {}

        async fn request_pin_code(&self, device: ObjectPath<'_>) -> Result<String, AgentError> {
            match self.ask(Ask::Pin, &device).await {
                Answer::Pin(pin) => Ok(pin),
                _ => Err(rejected()),
            }
        }

        async fn request_passkey(&self, device: ObjectPath<'_>) -> Result<u32, AgentError> {
            match self.ask(Ask::Passkey, &device).await {
                Answer::Pin(pin) => pin.trim().parse().ok().ok_or_else(rejected),
                _ => Err(rejected()),
            }
        }

        async fn request_confirmation(&self, device: ObjectPath<'_>, passkey: u32) -> Result<(), AgentError> {
            match self.ask(Ask::Confirm(passkey), &device).await {
                Answer::Confirm(true) => Ok(()),
                _ => Err(rejected()),
            }
        }

        // Nothing in the shell asks about an unpaired device connecting.
        fn request_authorization(&self, _device: ObjectPath<'_>) -> Result<(), AgentError> {
            Err(rejected())
        }

        fn authorize_service(&self, _device: ObjectPath<'_>, _uuid: &str) {}

        fn display_pin_code(&self, _device: ObjectPath<'_>, _pincode: &str) {}

        fn display_passkey(&self, _device: ObjectPath<'_>, _passkey: u32, _entered: u16) {}

        fn cancel(&self) {
            self.cancel.try_send(Answer::Cancel).ok();
        }
    }
}

use agent::Agent;

#[cfg(test)]
mod tests {
    use zbus::zvariant::Value;

    use super::{address_of, icon, Device};

    #[test]
    fn a_device_follows_its_own_changes() {
        let mut speaker = Device::default();
        speaker.set("Name", &Value::from("Speaker"));
        speaker.set("Paired", &Value::from(true));
        speaker.set("Icon", &Value::from("audio-card"));
        assert!(!speaker.connected);
        speaker.set("Connected", &Value::from(true));
        assert!(speaker.connected && speaker.paired);
        assert_eq!((speaker.shown_name(), speaker.icon), ("Speaker", "volume-2"));
        speaker.set("Connected", &Value::Bool(false));
        assert!(!speaker.connected);
    }

    #[test]
    fn icons_and_addresses_read_from_bluez() {
        assert_eq!(icon("audio-headphones"), "music");
        assert_eq!(icon("input-keyboard"), "keyboard");
        assert_eq!(icon(""), "bluetooth");
        assert_eq!(address_of("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"), "AA:BB:CC:DD:EE:FF");
    }
}
