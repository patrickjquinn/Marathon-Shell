//! `Network`: Wi-Fi, Ethernet, saved networks, the hotspot and
//! airplane mode. QML and the shell's C++ see the `QObject`; `NetworkManager`
//! is only ever read and driven from one actor on the I/O thread.

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::{stream, StreamExt};
use zbus::fdo::PropertiesProxy;
use zbus::message::Type as MessageType;
use zbus::names::InterfaceName;
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
        #[qproperty(bool, wifi_enabled, cxx_name = "wifiEnabled", READ, NOTIFY)]
        #[qproperty(bool, wifi_connected, cxx_name = "wifiConnected", READ, NOTIFY)]
        #[qproperty(QString, wifi_ssid, cxx_name = "wifiSsid", READ, NOTIFY)]
        #[qproperty(i32, wifi_signal_strength, cxx_name = "wifiSignalStrength", READ, NOTIFY)]
        #[qproperty(bool, ethernet_connected, cxx_name = "ethernetConnected", READ, NOTIFY)]
        #[qproperty(QString, ethernet_connection_name, cxx_name = "ethernetConnectionName", READ, NOTIFY)]
        #[qproperty(bool, wifi_available, cxx_name = "wifiAvailable", READ, NOTIFY)]
        #[qproperty(bool, bluetooth_available, cxx_name = "bluetoothAvailable", READ, NOTIFY)]
        #[qproperty(bool, wifi_available, cxx_name = "hotspotSupported", READ = hotspot_supported, NOTIFY = hotspot_supported_changed)]
        #[qproperty(bool, airplane_mode_enabled, cxx_name = "airplaneModeEnabled", READ, NOTIFY)]
        #[qproperty(bool, hotspot_active, cxx_name = "hotspotActive", READ = is_hotspot_active, NOTIFY = hotspot_active_changed)]
        #[qproperty(QList_QVariant, available_networks, cxx_name = "availableNetworks", READ, NOTIFY)]
        type Network = super::NetworkRust;

        #[cxx_name = "hotspotSupported"]
        fn hotspot_supported(self: &Network) -> bool;
        #[qinvokable]
        #[cxx_name = "isHotspotActive"]
        fn is_hotspot_active(self: &Network) -> bool;

        #[qsignal]
        #[cxx_name = "hotspotSupportedChanged"]
        fn hotspot_supported_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "hotspotActiveChanged"]
        fn hotspot_active_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "networkError"]
        fn network_error(self: Pin<&mut Self>, message: &QString);
        /// A requested connection reached ACTIVATED.
        #[qsignal]
        #[cxx_name = "connectionSuccess"]
        fn connection_success(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "connectionFailed"]
        fn connection_failed(self: Pin<&mut Self>, message: &QString);
        #[qsignal]
        #[cxx_name = "hotspotFailed"]
        fn hotspot_failed(self: Pin<&mut Self>, message: &QString);

        /// The chip's power save: idles between beacons while the
        /// association, and push sockets, stay up.
        #[qinvokable]
        #[cxx_name = "setWifiPowerSave"]
        fn set_wifi_power_save(self: &Network, on: bool);
        #[qinvokable]
        #[cxx_name = "enableWifi"]
        fn enable_wifi(self: &Network);
        #[qinvokable]
        #[cxx_name = "disableWifi"]
        fn disable_wifi(self: &Network);
        #[qinvokable]
        #[cxx_name = "toggleWifi"]
        fn toggle_wifi(self: &Network);
        #[qinvokable]
        #[cxx_name = "scanWifi"]
        fn scan_wifi(self: &Network);
        #[qinvokable]
        #[cxx_name = "connectToNetwork"]
        fn connect_to_network(self: &Network, ssid: &QString, password: &QString);
        /// `security`: "none", "wpa-psk" or "sae".
        #[qinvokable]
        #[cxx_name = "connectToHiddenNetwork"]
        fn connect_to_hidden_network(self: &Network, ssid: &QString, security: &QString, password: &QString);
        #[qinvokable]
        #[cxx_name = "disconnectWifi"]
        fn disconnect_wifi(self: &Network);
        /// Abandons a connection that has not reached ACTIVATED yet.
        #[qinvokable]
        #[cxx_name = "cancelPendingConnection"]
        fn cancel_pending_connection(self: &Network);
        /// Drops every saved profile for `ssid`.
        #[qinvokable]
        #[cxx_name = "forgetNetwork"]
        fn forget_network(self: &Network, ssid: &QString);
        #[qinvokable]
        #[cxx_name = "setAirplaneMode"]
        fn set_airplane_mode(self: Pin<&mut Network>, enabled: bool);
        #[qinvokable]
        #[cxx_name = "createHotspot"]
        fn create_hotspot(self: &Network, ssid: &QString, password: &QString);
        #[qinvokable]
        #[cxx_name = "stopHotspot"]
        fn stop_hotspot(self: &Network);
    }

    impl cxx_qt::Threading for Network {}
    impl cxx_qt::Initialize for Network {}
}

use qobject::Network;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct NetworkRust {
    wifi_enabled: bool,
    wifi_connected: bool,
    wifi_ssid: QString,
    wifi_signal_strength: i32,
    ethernet_connected: bool,
    ethernet_connection_name: QString,
    wifi_available: bool,
    bluetooth_available: bool,
    airplane_mode_enabled: bool,
    hotspot_active: bool,
    available_networks: QList<QVariant>,
    actor: Option<Sender<Command>>,
}



enum Command {
    Wifi(bool),
    Scan,
    Connect { ssid: String, password: String },
    ConnectHidden { ssid: String, security: String, password: String },
    Disconnect,
    CancelPending,
    Forget(String),
    Airplane(bool),
    CreateHotspot { ssid: String, password: String },
    StopHotspot,
}

/// An access point as QML sees it, the strongest of each SSID.
#[derive(Clone, Debug, PartialEq)]
struct AccessPoint {
    ssid: String,
    strength: u8,
    security: &'static str,
    frequency: u32,
    path: String,
    known: bool,
    connected: bool,
}

/// What is up, from the active connections.
#[derive(Clone, Default, PartialEq)]
struct Links {
    wifi: Option<String>,
    wifi_device: Option<OwnedObjectPath>,
    ethernet: Option<String>,
}

impl cxx_qt::Initialize for Network {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(32);
        io::spawn(run(self.qt_thread(), rx));
        self.as_mut().rust_mut().actor = Some(tx);
    }
}

impl Network {
    #[allow(clippy::unused_self, reason = "an invokable")]
    fn set_wifi_power_save(&self, on: bool) {
        // marathon-iw-setcap.service grants iw cap_net_admin.
        io::spawn(async move {
            let state = if on { "on" } else { "off" };
            let iw = ["dev", "wlan0", "set", "power_save", state];
            if let Err(e) = blocking::unblock(move || std::process::Command::new("/usr/sbin/iw").args(iw).status()).await {
                log::warn("network", format_args!("iw power_save {state}: {e}"));
            }
        });
    }

    fn hotspot_supported(&self) -> bool {
        self.wifi_available
    }

    fn is_hotspot_active(&self) -> bool {
        self.hotspot_active
    }

    fn send(&self, command: Command) {
        if self.actor.as_ref().is_none_or(|a| a.try_send(command).is_err()) {
            log::warn("network", "no network backend");
        }
    }

    fn enable_wifi(&self) {
        self.send(Command::Wifi(true));
    }

    fn disable_wifi(&self) {
        self.send(Command::Wifi(false));
    }

    fn toggle_wifi(&self) {
        self.send(Command::Wifi(!self.wifi_enabled));
    }

    fn scan_wifi(&self) {
        self.send(Command::Scan);
    }

    fn connect_to_network(&self, ssid: &QString, password: &QString) {
        self.send(Command::Connect { ssid: ssid.to_string(), password: password.to_string() });
    }

    fn connect_to_hidden_network(&self, ssid: &QString, security: &QString, password: &QString) {
        self.send(Command::ConnectHidden {
            ssid: ssid.to_string(),
            security: security.to_string(),
            password: password.to_string(),
        });
    }

    fn disconnect_wifi(&self) {
        self.send(Command::Disconnect);
    }

    fn cancel_pending_connection(&self) {
        self.send(Command::CancelPending);
    }

    fn forget_network(&self, ssid: &QString) {
        self.send(Command::Forget(ssid.to_string()));
    }

    // Airplane mode is the kernel's rfkill switches for every radio; Wi-Fi
    // follows at once so the tile does.
    fn set_airplane_mode(mut self: Pin<&mut Self>, enabled: bool) {
        self.send(Command::Airplane(enabled));
        if self.wifi_enabled == enabled {
            self.as_mut().rust_mut().wifi_enabled = !enabled;
            self.as_mut().wifi_enabled_changed();
        }
        self.as_mut().rust_mut().airplane_mode_enabled = enabled;
        self.airplane_mode_enabled_changed();
    }

    fn create_hotspot(&self, ssid: &QString, password: &QString) {
        self.send(Command::CreateHotspot { ssid: ssid.to_string(), password: password.to_string() });
    }

    fn stop_hotspot(&self) {
        self.send(Command::StopHotspot);
    }

    fn apply_hardware(mut self: Pin<&mut Self>, wifi: bool, bluetooth: bool) {
        if self.wifi_available != wifi {
            self.as_mut().rust_mut().wifi_available = wifi;
            self.as_mut().wifi_available_changed();
            self.as_mut().hotspot_supported_changed();
        }
        if self.bluetooth_available != bluetooth {
            self.as_mut().rust_mut().bluetooth_available = bluetooth;
            self.as_mut().bluetooth_available_changed();
        }
    }

    // Always emitted: a pending switch waits for the answer either way.
    fn apply_wifi_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        self.as_mut().rust_mut().wifi_enabled = enabled;
        self.wifi_enabled_changed();
    }

    fn apply_links(mut self: Pin<&mut Self>, links: Links) {
        let connected = links.wifi.is_some();
        if self.wifi_connected != connected {
            self.as_mut().rust_mut().wifi_connected = connected;
            self.as_mut().wifi_connected_changed();
        }
        if let Some(ssid) = links.wifi.filter(|s| !s.is_empty()) {
            if self.wifi_ssid.to_string() != ssid {
                self.as_mut().rust_mut().wifi_ssid = QString::from(ssid.as_str());
                self.as_mut().wifi_ssid_changed();
            }
        }
        let ethernet = links.ethernet.is_some();
        if self.ethernet_connected != ethernet {
            self.as_mut().rust_mut().ethernet_connected = ethernet;
            self.as_mut().ethernet_connected_changed();
        }
        if let Some(name) = links.ethernet.filter(|s| !s.is_empty()) {
            if self.ethernet_connection_name.to_string() != name {
                self.as_mut().rust_mut().ethernet_connection_name = QString::from(name.as_str());
                self.as_mut().ethernet_connection_name_changed();
            }
        }
    }

    fn apply_strength(mut self: Pin<&mut Self>, strength: u8) {
        if self.wifi_signal_strength != i32::from(strength) {
            self.as_mut().rust_mut().wifi_signal_strength = i32::from(strength);
            self.wifi_signal_strength_changed();
        }
    }

    fn apply_networks(mut self: Pin<&mut Self>, networks: &[AccessPoint]) {
        let mut list = QList::<QVariant>::default();
        list.reserve(isize::try_from(networks.len()).unwrap_or(0));
        for n in networks {
            list.append(QVariant::from(&n.to_map()));
        }
        self.as_mut().rust_mut().available_networks = list;
        self.available_networks_changed();
    }

    fn apply_hotspot(mut self: Pin<&mut Self>, active: bool) {
        if self.hotspot_active != active {
            self.as_mut().rust_mut().hotspot_active = active;
            self.hotspot_active_changed();
        }
    }
}

impl AccessPoint {
    fn to_map(&self) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        let mut put = |key: &str, value: QVariant| map.insert(QString::from(key), value);
        put("ssid", QVariant::from(&QString::from(self.ssid.as_str())));
        put("strength", QVariant::from(&i32::from(self.strength)));
        put("secured", QVariant::from(&(self.security != "Open")));
        put("security", QVariant::from(&QString::from(self.security)));
        put("frequency", QVariant::from(&i32::try_from(self.frequency).unwrap_or(0)));
        put("path", QVariant::from(&QString::from(self.path.as_str())));
        put("connected", QVariant::from(&self.connected));
        put("known", QVariant::from(&self.known));
        map
    }
}

const NM: &str = "org.freedesktop.NetworkManager";
const ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const ACCESS_POINT: &str = "org.freedesktop.NetworkManager.AccessPoint";
const HOTSPOT_UUID: &str = "5f7c2a3e-8d1b-4c6e-9a0f-3b2d1e4c5a60";
// Active connection states.
const ACTIVATED: u32 = 2;
const DEACTIVATED: u32 = 4;
// Device types.
const WIFI: u32 = 2;
const BLUETOOTH: u32 = 5;

#[zbus::proxy(interface = "org.freedesktop.NetworkManager", default_service = "org.freedesktop.NetworkManager", default_path = "/org/freedesktop/NetworkManager")]
trait Nm {
    fn get_devices(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
    fn activate_connection(&self, connection: &ObjectPath<'_>, device: &ObjectPath<'_>, specific: &ObjectPath<'_>) -> zbus::Result<OwnedObjectPath>;
    fn add_and_activate_connection(&self, settings: Settings<'_>, device: &ObjectPath<'_>, specific: &ObjectPath<'_>) -> zbus::Result<(OwnedObjectPath, OwnedObjectPath)>;
    fn deactivate_connection(&self, active: &ObjectPath<'_>) -> zbus::Result<()>;
    #[zbus(property)]
    fn wireless_enabled(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn set_wireless_enabled(&self, enabled: bool) -> zbus::Result<()>;
    #[zbus(property)]
    fn active_connections(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Device", default_service = "org.freedesktop.NetworkManager")]
trait Device {
    fn disconnect(&self) -> zbus::Result<()>;
    #[zbus(property)]
    fn device_type(&self) -> zbus::Result<u32>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Device.Wireless", default_service = "org.freedesktop.NetworkManager")]
trait Wireless {
    fn request_scan(&self, options: HashMap<&str, Value<'_>>) -> zbus::Result<()>;
    fn get_all_access_points(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
    #[zbus(property)]
    fn active_access_point(&self) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Settings", default_service = "org.freedesktop.NetworkManager", default_path = "/org/freedesktop/NetworkManager/Settings")]
trait NmSettings {
    fn list_connections(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
    fn get_connection_by_uuid(&self, uuid: &str) -> zbus::Result<OwnedObjectPath>;
    #[zbus(signal)]
    fn new_connection(&self, connection: ObjectPath<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    fn connection_removed(&self, connection: ObjectPath<'_>) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Settings.Connection", default_service = "org.freedesktop.NetworkManager")]
trait SavedConnection {
    fn get_settings(&self) -> zbus::Result<HashMap<String, HashMap<String, OwnedValue>>>;
    fn update(&self, settings: Settings<'_>) -> zbus::Result<()>;
    fn delete(&self) -> zbus::Result<()>;
}

/// `NetworkManager`'s connection settings, `a{sa{sv}}`.
type Settings<'a> = HashMap<&'a str, HashMap<&'a str, Value<'a>>>;

fn wifi_settings<'a>(ssid: &'a str, key_mgmt: Option<&'a str>, password: &'a str, hidden: bool) -> Settings<'a> {
    let mut wireless = HashMap::from([("ssid", Value::from(ssid.as_bytes())), ("mode", Value::from("infrastructure"))]);
    if hidden {
        wireless.insert("hidden", Value::from(true));
    }
    let mut settings = HashMap::from([
        (
            "connection",
            HashMap::from([
                ("type", Value::from("802-11-wireless")),
                ("uuid", Value::from(new_uuid())),
                ("id", Value::from(ssid)),
                ("autoconnect", Value::from(true)),
            ]),
        ),
        ("802-11-wireless", wireless),
        ("ipv4", HashMap::from([("method", Value::from("auto"))])),
        ("ipv6", HashMap::from([("method", Value::from("auto"))])),
    ]);
    if let Some(key_mgmt) = key_mgmt {
        settings.insert(
            "802-11-wireless-security",
            HashMap::from([("key-mgmt", Value::from(key_mgmt)), ("psk", Value::from(password))]),
        );
    }
    settings
}

fn hotspot_settings<'a>(ssid: &'a str, password: &'a str) -> Settings<'a> {
    let mut settings = HashMap::from([
        (
            "connection",
            HashMap::from([
                ("type", Value::from("802-11-wireless")),
                ("uuid", Value::from(HOTSPOT_UUID)),
                ("id", Value::from("Marathon hotspot")),
                ("autoconnect", Value::from(false)),
            ]),
        ),
        (
            "802-11-wireless",
            HashMap::from([("ssid", Value::from(ssid.as_bytes())), ("mode", Value::from("ap")), ("band", Value::from("bg"))]),
        ),
        ("ipv4", HashMap::from([("method", Value::from("shared"))])),
        ("ipv6", HashMap::from([("method", Value::from("ignore"))])),
    ]);
    if password.chars().count() >= 8 {
        settings.insert(
            "802-11-wireless-security",
            HashMap::from([("key-mgmt", Value::from("wpa-psk")), ("psk", Value::from(password))]),
        );
    }
    settings
}

/// The kernel makes UUIDs; no crate needed for one per new profile.
fn new_uuid() -> String {
    io::read("/proc/sys/kernel/random/uuid").unwrap_or_default()
}

fn security(wpa_flags: u32, rsn_flags: u32) -> &'static str {
    if rsn_flags != 0 {
        "WPA2/WPA3"
    } else if wpa_flags != 0 {
        "WPA"
    } else {
        "Open"
    }
}

/// What the person reads when `NetworkManager` refuses an activation.
fn activation_error(name: &str, message: &str) -> String {
    if name.contains("InvalidArgs") || message.contains("not allowed") {
        "Connection rejected by NetworkManager (bad config)".to_owned()
    } else if ["secrets-required", "no-secrets", "not authorized"].iter().any(|m| message.contains(m)) {
        "Incorrect password".to_owned()
    } else if message.contains("timeout") {
        "Connection timeout".to_owned()
    } else if message.contains("not-found") {
        "Network not found".to_owned()
    } else if !message.is_empty() {
        format!("Failed: {message}")
    } else {
        format!("Failed ({name})")
    }
}

/// An active connection's reason for going down, for the person.
fn deactivation_error(reason: u32) -> &'static str {
    const CONNECT_TIMEOUT: u32 = 6;
    const NO_SECRETS: u32 = 9;
    const LOGIN_FAILED: u32 = 10;
    match reason {
        NO_SECRETS | LOGIN_FAILED => "Incorrect password",
        CONNECT_TIMEOUT => "Connection timeout",
        _ => "Couldn't connect",
    }
}

/// The strongest access point per SSID, connected first, then by strength.
fn merge(mut aps: Vec<AccessPoint>) -> Vec<AccessPoint> {
    aps.sort_by(|a, b| b.connected.cmp(&a.connected).then(b.strength.cmp(&a.strength)));
    let mut seen = std::collections::HashSet::new();
    aps.retain(|n| seen.insert(n.ssid.clone()));
    aps
}

type Qt = cxx_qt::CxxQtThread<Network>;

enum Event {
    Command(Command),
    Closed,
    WirelessEnabled(bool),
    ActiveChanged,
    ActiveState { path: OwnedObjectPath, state: u32, reason: u32 },
    Saved,
    Strength { path: OwnedObjectPath, strength: u8 },
    Rescan,
}

struct Pending {
    ssid: String,
    path: Option<OwnedObjectPath>,
    cancelled: bool,
}

struct Actor {
    qt: Qt,
    bus: zbus::Connection,
    nm: NmProxy<'static>,
    wifi_device: Option<OwnedObjectPath>,
    saved: HashMap<String, Vec<OwnedObjectPath>>,
    networks: Vec<AccessPoint>,
    links: Links,
    active_ap: Option<OwnedObjectPath>,
    pending: Option<Pending>,
    hotspot: Option<OwnedObjectPath>,
    hotspot_active: bool,
    rescan: Sender<Event>,
}

async fn run(qt: Qt, commands: Receiver<Command>) {
    let bus = match io::system_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("network", format_args!("no system bus: {e}")),
    };
    let nm = match NmProxy::new(&bus).await {
        Ok(nm) => nm,
        Err(e) => return log::warn("network", format_args!("no NetworkManager: {e}")),
    };
    let (rescan, rescans) = async_channel::bounded(4);
    let mut actor = Actor {
        qt,
        bus,
        nm,
        wifi_device: None,
        saved: HashMap::new(),
        networks: Vec::new(),
        links: Links::default(),
        active_ap: None,
        pending: None,
        hotspot: None,
        hotspot_active: false,
        rescan,
    };
    actor.detect_hardware().await;
    if let Ok(enabled) = actor.nm.wireless_enabled().await {
        actor.qt.queue(move |obj| obj.apply_wifi_enabled(enabled)).ok();
    }
    actor.refresh_links().await;
    actor.refresh_saved().await;
    actor.scan().await;

    let events = commands
        .map(Event::Command)
        .chain(stream::once(Event::Closed))
        .or(actor.nm_events().await)
        .or(actor.signal_events().await)
        .or(rescans)
        .or(Timer::interval(Duration::from_secs(30)).map(|_| Event::Rescan));
    let mut events = std::pin::pin!(events);
    while let Some(event) = events.next().await {
        match event {
            Event::Command(command) => actor.handle(command).await,
            Event::Closed => break,
            Event::WirelessEnabled(enabled) => {
                actor.qt.queue(move |obj| obj.apply_wifi_enabled(enabled)).ok();
            }
            Event::ActiveChanged => actor.refresh_links().await,
            Event::ActiveState { path, state, reason } => actor.on_active_state(&path, state, reason).await,
            Event::Saved => actor.refresh_saved().await,
            Event::Strength { path, strength } => {
                if actor.active_ap.as_ref() == Some(&path) {
                    actor.qt.queue(move |obj| obj.apply_strength(strength)).ok();
                }
            }
            Event::Rescan => actor.scan().await,
        }
    }
}

impl Actor {
    async fn props(&self, path: &OwnedObjectPath) -> Option<PropertiesProxy<'static>> {
        PropertiesProxy::builder(&self.bus)
            .destination(NM)
            .and_then(|b| b.path(path.clone()))
            .map(|b| b.cache_properties(zbus::proxy::CacheProperties::No))
            .ok()?
            .build()
            .await
            .ok()
    }

    async fn get_all(&self, path: &OwnedObjectPath, interface: &'static str) -> HashMap<String, OwnedValue> {
        let Some(props) = self.props(path).await else { return HashMap::new() };
        let Ok(interface) = InterfaceName::try_from(interface) else { return HashMap::new() };
        props.get_all(interface).await.unwrap_or_default()
    }

    async fn detect_hardware(&mut self) {
        let devices = match self.nm.get_devices().await {
            Ok(d) => d,
            Err(e) => return log::warn("network", format_args!("no devices: {e}")),
        };
        let (mut wifi, mut bluetooth) = (false, false);
        for path in devices {
            let Ok(device) = DeviceProxy::builder(&self.bus).path(path.clone()) else { continue };
            let Ok(device) = device.cache_properties(zbus::proxy::CacheProperties::No).build().await else { continue };
            match device.device_type().await {
                Ok(WIFI) => {
                    wifi = true;
                    self.wifi_device = Some(path);
                }
                Ok(BLUETOOTH) => bluetooth = true,
                _ => {}
            }
        }
        self.qt.queue(move |obj| obj.apply_hardware(wifi, bluetooth)).ok();
    }

    async fn handle(&mut self, command: Command) {
        match command {
            Command::Wifi(enabled) => {
                // WirelessEnabled is the wlan-only switch; Enable() would
                // sleep the modem and ethernet too.
                let result = self.nm.set_wireless_enabled(enabled).await;
                let now = if let Err(e) = result {
                    log::warn("network", format_args!("WirelessEnabled: {e}"));
                    let message = if enabled { "Failed to enable WiFi" } else { "Failed to disable WiFi" };
                    self.qt.queue(move |obj| obj.network_error(&QString::from(message))).ok();
                    !enabled
                } else {
                    enabled
                };
                self.qt.queue(move |obj| obj.apply_wifi_enabled(now)).ok();
            }
            Command::Scan => self.request_scan().await,
            Command::Connect { ssid, password } => self.connect(ssid, &password).await,
            Command::ConnectHidden { ssid, security, password } => {
                self.forget(&ssid).await;
                let key_mgmt = (security != "none").then_some(security.as_str());
                let settings = wifi_settings(&ssid, key_mgmt, &password, true);
                self.add_and_activate(ssid.clone(), settings).await;
            }
            Command::Disconnect => {
                let Some(path) = self.wifi_device.clone() else { return };
                let disconnected = match DeviceProxy::builder(&self.bus).path(path) {
                    Ok(b) => match b.cache_properties(zbus::proxy::CacheProperties::No).build().await {
                        Ok(device) => device.disconnect().await,
                        Err(e) => Err(e),
                    },
                    Err(e) => Err(e),
                };
                if let Err(e) = disconnected {
                    log::warn("network", format_args!("disconnect: {e}"));
                    self.qt.queue(|obj| obj.network_error(&QString::from("Failed to disconnect Wi-Fi"))).ok();
                }
            }
            Command::CancelPending => {
                if let Some(pending) = &mut self.pending {
                    match pending.path.take() {
                        Some(path) => {
                            self.pending = None;
                            if let Err(e) = self.nm.deactivate_connection(&path).await {
                                log::warn("network", format_args!("cancel connect: {e}"));
                            }
                        }
                        // The activation reply is still on its way.
                        None => pending.cancelled = true,
                    }
                }
            }
            Command::Forget(ssid) => self.forget(&ssid).await,
            Command::Airplane(enabled) => {
                if set_rfkill(&["wlan", "wwan", "bluetooth"], enabled) == 0 {
                    log::warn("network", "airplane mode: no rfkill switch answered");
                }
                if let Err(e) = self.nm.set_wireless_enabled(!enabled).await {
                    log::warn("network", format_args!("WirelessEnabled: {e}"));
                }
            }
            Command::CreateHotspot { ssid, password } => self.create_hotspot(&ssid, &password).await,
            Command::StopHotspot => {
                if let Some(path) = self.hotspot.take() {
                    if let Err(e) = self.nm.deactivate_connection(&path).await {
                        log::warn("network", format_args!("hotspot stop: {e}"));
                    }
                }
                self.set_hotspot(false);
            }
        }
    }

    async fn wireless(&self) -> Option<WirelessProxy<'static>> {
        let path = self.wifi_device.clone()?;
        WirelessProxy::builder(&self.bus).path(path).ok()?.cache_properties(zbus::proxy::CacheProperties::No).build().await.ok()
    }

    async fn request_scan(&mut self) {
        let Some(wireless) = self.wireless().await else { return };
        // The list comes back once NetworkManager has heard the new beacons.
        let delay = match wireless.request_scan(HashMap::new()).await {
            Ok(()) => Duration::from_secs(2),
            Err(e) => {
                log::warn("network", format_args!("scan: {e}"));
                self.qt.queue(|obj| obj.network_error(&QString::from("Failed to scan for networks"))).ok();
                Duration::from_millis(250)
            }
        };
        let rescan = self.rescan.clone();
        io::spawn(async move {
            Timer::after(delay).await;
            rescan.send(Event::Rescan).await.ok();
        });
    }

    async fn scan(&mut self) {
        let Some(wireless) = self.wireless().await else { return };
        let Ok(paths) = wireless.get_all_access_points().await else { return };
        let mut aps = Vec::with_capacity(paths.len());
        for path in paths {
            let props = self.get_all(&path, ACCESS_POINT).await;
            let get_u32 = |k: &str| props.get(k).and_then(|v| u32::try_from(v).ok()).unwrap_or(0);
            let ssid = props
                .get("Ssid")
                .and_then(|v| Vec::<u8>::try_from(v.try_clone().ok()?).ok())
                .map(|b| String::from_utf8_lossy(&b).into_owned())
                .unwrap_or_default();
            if ssid.is_empty() {
                continue;
            }
            let strength = props.get("Strength").and_then(|v| u8::try_from(v).ok()).unwrap_or(0);
            aps.push(AccessPoint {
                connected: self.links.wifi.as_deref() == Some(ssid.as_str()),
                known: self.saved.contains_key(&ssid),
                ssid,
                strength,
                security: security(get_u32("WpaFlags"), get_u32("RsnFlags")),
                frequency: get_u32("Frequency"),
                path: path.to_string(),
            });
        }
        self.networks = merge(aps);
        self.publish_networks();
    }

    fn publish_networks(&self) {
        let networks = self.networks.clone();
        self.qt.queue(move |obj| obj.apply_networks(&networks)).ok();
    }

    async fn refresh_links(&mut self) {
        let mut links = Links::default();
        for path in self.nm.active_connections().await.unwrap_or_default() {
            let props = self.get_all(&path, ACTIVE).await;
            let text = |k: &str| props.get(k).and_then(|v| String::try_from(v.try_clone().ok()?).ok()).unwrap_or_default();
            if props.get("State").and_then(|v| u32::try_from(v).ok()) != Some(ACTIVATED) {
                continue;
            }
            match text("Type").as_str() {
                "802-11-wireless" => {
                    links.wifi = Some(text("Id"));
                    links.wifi_device = props
                        .get("Devices")
                        .and_then(|v| Vec::<OwnedObjectPath>::try_from(v.try_clone().ok()?).ok())
                        .and_then(|d| d.into_iter().next());
                }
                "802-3-ethernet" => links.ethernet = Some(text("Id")),
                _ => {}
            }
        }
        if let (Some(pending), Some(ssid)) = (&self.pending, &links.wifi) {
            if &pending.ssid == ssid {
                self.pending = None;
                self.qt.queue(Network::connection_success).ok();
            }
        }
        if links != self.links {
            self.links = links.clone();
            self.qt.queue(move |obj| obj.apply_links(links)).ok();
            for n in &mut self.networks {
                n.connected = self.links.wifi.as_deref() == Some(n.ssid.as_str());
            }
            self.publish_networks();
        }
        self.follow_access_point().await;
    }

    async fn follow_access_point(&mut self) {
        let Some(device) = self.links.wifi_device.clone() else {
            self.active_ap = None;
            return;
        };
        let Ok(builder) = WirelessProxy::builder(&self.bus).path(device) else { return };
        let Ok(wireless) = builder.cache_properties(zbus::proxy::CacheProperties::No).build().await else { return };
        let Ok(ap) = wireless.active_access_point().await else { return };
        if ap.as_str() == "/" {
            return;
        }
        let props = self.get_all(&ap, ACCESS_POINT).await;
        if let Some(strength) = props.get("Strength").and_then(|v| u8::try_from(v).ok()) {
            self.qt.queue(move |obj| obj.apply_strength(strength)).ok();
        }
        self.active_ap = Some(ap);
    }

    async fn refresh_saved(&mut self) {
        let Ok(settings) = NmSettingsProxy::new(&self.bus).await else { return };
        let Ok(paths) = settings.list_connections().await else { return };
        let mut saved: HashMap<String, Vec<OwnedObjectPath>> = HashMap::new();
        for path in paths {
            let Ok(builder) = SavedConnectionProxy::builder(&self.bus).path(path.clone()) else { continue };
            let Ok(connection) = builder.build().await else { continue };
            let Ok(all) = connection.get_settings().await else { continue };
            let Some(wireless) = all.get("802-11-wireless") else { continue };
            let mode = wireless.get("mode").and_then(|v| String::try_from(v.try_clone().ok()?).ok());
            if mode.as_deref() == Some("ap") {
                continue;
            }
            let ssid = wireless
                .get("ssid")
                .and_then(|v| Vec::<u8>::try_from(v.try_clone().ok()?).ok())
                .map(|b| String::from_utf8_lossy(&b).into_owned())
                .unwrap_or_default();
            if !ssid.is_empty() {
                saved.entry(ssid).or_default().push(path);
            }
        }
        self.saved = saved;
        for n in &mut self.networks {
            n.known = self.saved.contains_key(&n.ssid);
        }
        self.publish_networks();
    }

    async fn forget(&mut self, ssid: &str) {
        for path in self.saved.remove(ssid).unwrap_or_default() {
            let Ok(builder) = SavedConnectionProxy::builder(&self.bus).path(path) else { continue };
            if let Ok(connection) = builder.build().await {
                if let Err(e) = connection.delete().await {
                    log::warn("network", format_args!("forget {ssid}: {e}"));
                }
            }
        }
    }

    async fn connect(&mut self, ssid: String, password: &str) {
        let (Some(device), Some(ap)) = (self.wifi_device.clone(), self.networks.iter().find(|n| n.ssid == ssid)) else {
            let message = if self.wifi_device.is_none() { "WiFi not available" } else { "Network not found" };
            self.qt.queue(move |obj| obj.connection_failed(&QString::from(message))).ok();
            return;
        };
        let (ap_path, secured) = (ap.path.clone(), ap.security != "Open");
        let saved = self.saved.get(&ssid).cloned().unwrap_or_default();
        if let (Some(profile), true) = (saved.first(), password.is_empty()) {
            let Ok(ap_path) = ObjectPath::try_from(ap_path.as_str()) else { return };
            let result = self.nm.activate_connection(profile, &device, &ap_path).await;
            self.on_activating(ssid, result).await;
            return;
        }
        // A new password replaces the saved profile instead of adding another.
        self.forget(&ssid).await;
        let key_mgmt = (secured && !password.is_empty()).then_some("wpa-psk");
        let settings = wifi_settings(&ssid, key_mgmt, password, false);
        let Ok(ap_path) = ObjectPath::try_from(ap_path.as_str()) else { return };
        let result = self.nm.add_and_activate_connection(settings, &device, &ap_path).await.map(|(_, active)| active);
        self.on_activating(ssid, result).await;
    }

    async fn add_and_activate(&mut self, ssid: String, settings: Settings<'_>) {
        let Some(device) = self.wifi_device.clone() else {
            self.qt.queue(|obj| obj.connection_failed(&QString::from("WiFi not available"))).ok();
            return;
        };
        let result = self
            .nm
            .add_and_activate_connection(settings, &device, &ObjectPath::from_static_str_unchecked("/"))
            .await
            .map(|(_, active)| active);
        self.on_activating(ssid, result).await;
    }

    // Accepted only: authentication and DHCP haven't run. The active
    // connection's state says how it ends.
    async fn on_activating(&mut self, ssid: String, result: zbus::Result<OwnedObjectPath>) {
        let cancelled = self.pending.as_ref().is_some_and(|p| p.cancelled && p.ssid == ssid);
        match result {
            Err(e) => {
                self.pending = None;
                if !cancelled {
                    let message = match &e {
                        zbus::Error::MethodError(name, text, _) => activation_error(name.as_str(), text.as_deref().unwrap_or("")),
                        other => activation_error("", &other.to_string()),
                    };
                    log::warn("network", format_args!("activation failed: {e}"));
                    self.qt.queue(move |obj| obj.connection_failed(&QString::from(message.as_str()))).ok();
                }
            }
            Ok(path) if cancelled => {
                self.pending = None;
                self.nm.deactivate_connection(&path).await.ok();
            }
            Ok(path) => {
                self.pending = Some(Pending { ssid, path: Some(path), cancelled: false });
                self.refresh_links().await;
            }
        }
    }

    async fn on_active_state(&mut self, path: &OwnedObjectPath, state: u32, reason: u32) {
        if self.hotspot.as_ref() == Some(path) {
            self.on_hotspot_state(state);
        }
        let pending_here = self.pending.as_ref().and_then(|p| p.path.as_ref()) == Some(path);
        if pending_here && state == DEACTIVATED {
            self.pending = None;
            self.qt.queue(move |obj| obj.connection_failed(&QString::from(deactivation_error(reason)))).ok();
        }
        self.refresh_links().await;
    }

    async fn create_hotspot(&mut self, ssid: &str, password: &str) {
        let Some(device) = self.wifi_device.clone() else {
            self.qt.queue(|obj| obj.hotspot_failed(&QString::from("Wi-Fi is not available"))).ok();
            return;
        };
        let no_ap = ObjectPath::from_static_str_unchecked("/");
        // One saved profile under a fixed UUID, updated and reactivated each time.
        let profile = match NmSettingsProxy::new(&self.bus).await {
            Ok(settings) => settings.get_connection_by_uuid(HOTSPOT_UUID).await.ok(),
            Err(_) => None,
        };
        let activated = match profile {
            Some(profile) => {
                let updated = match SavedConnectionProxy::builder(&self.bus).path(profile.clone()) {
                    Ok(b) => match b.build().await {
                        Ok(saved) => saved.update(hotspot_settings(ssid, password)).await,
                        Err(e) => Err(e),
                    },
                    Err(e) => Err(e),
                };
                match updated {
                    Ok(()) => self.nm.activate_connection(&profile, &device, &no_ap).await,
                    Err(e) => Err(e),
                }
            }
            None => self
                .nm
                .add_and_activate_connection(hotspot_settings(ssid, password), &device, &no_ap)
                .await
                .map(|(_, active)| active),
        };
        match activated {
            Ok(path) => {
                let state = self.get_all(&path, ACTIVE).await.get("State").and_then(|v| u32::try_from(v).ok());
                self.hotspot = Some(path);
                self.on_hotspot_state(state.unwrap_or(0));
            }
            Err(e) => {
                log::warn("network", format_args!("hotspot: {e}"));
                let message = e.to_string();
                self.qt.queue(move |obj| obj.hotspot_failed(&QString::from(message.as_str()))).ok();
            }
        }
    }

    fn on_hotspot_state(&mut self, state: u32) {
        match state {
            ACTIVATED => self.set_hotspot(true),
            DEACTIVATED => {
                let was_active = self.hotspot_active;
                self.hotspot = None;
                self.set_hotspot(false);
                if !was_active {
                    self.qt
                        .queue(|obj| obj.hotspot_failed(&QString::from("The Wi-Fi adapter could not start an access point")))
                        .ok();
                }
            }
            _ => {}
        }
    }

    fn set_hotspot(&mut self, active: bool) {
        self.hotspot_active = active;
        self.qt.queue(move |obj| obj.apply_hotspot(active)).ok();
    }

    // NetworkManager's own properties, as zbus's cache sees them change.
    async fn nm_events(&self) -> stream::Boxed<Event> {
        let enabled = self
            .nm
            .receive_wireless_enabled_changed()
            .await
            .then(|change| async move { change.get().await.ok().map(Event::WirelessEnabled) })
            .filter_map(|event| event);
        let active = self.nm.receive_active_connections_changed().await.map(|_| Event::ActiveChanged);
        enabled.or(active).boxed()
    }

    // Signals from objects that come and go: every active connection's
    // state, saved profiles, and access points' strength.
    async fn signal_events(&self) -> stream::Boxed<Event> {
        let rule = |interface: &'static str, member: &'static str, namespace: &'static str| {
            MatchRule::builder()
                .msg_type(MessageType::Signal)
                .sender(NM)
                .and_then(|b| b.interface(interface))
                .and_then(|b| b.member(member))
                .and_then(|b| b.path_namespace(namespace))
                .map(zbus::match_rule::Builder::build)
        };
        let mut merged = stream::empty().boxed();
        if let Ok(rule) = rule(ACTIVE, "StateChanged", "/org/freedesktop/NetworkManager/ActiveConnection") {
            if let Ok(s) = MessageStream::for_match_rule(rule, &self.bus, Some(64)).await {
                let states = s.filter_map(|m| {
                    let m = m.ok()?;
                    let path = OwnedObjectPath::from(m.header().path()?.clone());
                    let (state, reason): (u32, u32) = m.body().deserialize().ok()?;
                    Some(Event::ActiveState { path, state, reason })
                });
                merged = merged.or(states).boxed();
            }
        }
        if let Ok(rule) = rule("org.freedesktop.DBus.Properties", "PropertiesChanged", "/org/freedesktop/NetworkManager/AccessPoint") {
            if let Ok(s) = MessageStream::for_match_rule(rule, &self.bus, Some(64)).await {
                let strengths = s.filter_map(|m| {
                    let m = m.ok()?;
                    let path = OwnedObjectPath::from(m.header().path()?.clone());
                    let (_, changed, _): (String, HashMap<String, OwnedValue>, Vec<String>) = m.body().deserialize().ok()?;
                    let strength = u8::try_from(changed.get("Strength")?).ok()?;
                    Some(Event::Strength { path, strength })
                });
                merged = merged.or(strengths).boxed();
            }
        }
        if let Ok(settings) = NmSettingsProxy::new(&self.bus).await {
            if let (Ok(added), Ok(removed)) = (settings.receive_new_connection().await, settings.receive_connection_removed().await) {
                merged = merged.or(added.map(|_| Event::Saved)).or(removed.map(|_| Event::Saved)).boxed();
            }
        }
        merged
    }
}

/// Soft-blocks or unblocks every rfkill switch of the given types; the
/// number of switches written. sysfs, not the rfkill CLI, which aborts on
/// some rows.
fn set_rfkill(types: &[&str], block: bool) -> usize {
    let Ok(entries) = std::fs::read_dir("/sys/class/rfkill") else { return 0 };
    entries
        .filter_map(Result::ok)
        .filter(|e| {
            io::read::<String>(e.path().join("type")).is_some_and(|t| types.contains(&t.as_str()))
        })
        .filter(|e| std::fs::write(e.path().join("soft"), if block { "1\n" } else { "0\n" }).is_ok())
        .count()
}

#[cfg(test)]
mod tests {
    use super::{activation_error, deactivation_error, merge, security, AccessPoint};

    fn ap(ssid: &str, strength: u8, connected: bool) -> AccessPoint {
        AccessPoint {
            ssid: ssid.to_owned(),
            strength,
            security: "WPA2/WPA3",
            frequency: 2412,
            path: format!("/ap/{ssid}{strength}"),
            known: false,
            connected,
        }
    }

    #[test]
    fn each_ssid_shows_once_at_its_strongest_connected_first() {
        let merged = merge(vec![ap("Cafe", 40, false), ap("Home", 30, true), ap("Cafe", 70, false), ap("Home", 20, true)]);
        let shown: Vec<(&str, u8)> = merged.iter().map(|n| (n.ssid.as_str(), n.strength)).collect();
        assert_eq!(shown, [("Home", 30), ("Cafe", 70)]);
    }

    #[test]
    fn security_reads_from_the_flags() {
        assert_eq!(security(0, 0), "Open");
        assert_eq!(security(0x8, 0), "WPA");
        assert_eq!(security(0x8, 0x188), "WPA2/WPA3");
    }

    #[test]
    fn errors_read_as_the_person_needs_them() {
        assert_eq!(activation_error("org.freedesktop.NetworkManager.InvalidArgs", ""), "Connection rejected by NetworkManager (bad config)");
        assert_eq!(activation_error("x", "802-1x: no-secrets"), "Incorrect password");
        assert_eq!(activation_error("x", "activation timeout"), "Connection timeout");
        assert_eq!(activation_error("org.x.Failed", ""), "Failed (org.x.Failed)");
        assert_eq!(deactivation_error(9), "Incorrect password");
        assert_eq!(deactivation_error(6), "Connection timeout");
        assert_eq!(deactivation_error(1), "Couldn't connect");
    }
}
