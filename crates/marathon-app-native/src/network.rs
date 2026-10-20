//! `Network`: the shell's Network1, Wi-Fi, Ethernet, the hotspot and
//! airplane mode.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QVariant};

use crate::shell::{get, mirror, relay, Service, Update};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
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
        #[qproperty(bool, hotspot_supported, cxx_name = "hotspotSupported", READ, NOTIFY)]
        #[qproperty(bool, hotspot_active, cxx_name = "hotspotActive", READ, NOTIFY)]
        #[qproperty(bool, airplane_mode_enabled, cxx_name = "airplaneModeEnabled", READ, NOTIFY)]
        #[qproperty(QList_QVariant, available_networks, cxx_name = "availableNetworks", READ, NOTIFY)]
        type Network = super::NetworkRust;

        #[qsignal]
        #[cxx_name = "networkError"]
        fn network_error(self: Pin<&mut Self>, message: &QString);
        #[qsignal]
        #[cxx_name = "connectionSuccess"]
        fn connection_success(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "connectionFailed"]
        fn connection_failed(self: Pin<&mut Self>, message: &QString);

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
        #[qinvokable]
        #[cxx_name = "connectToHiddenNetwork"]
        fn connect_to_hidden_network(self: &Network, ssid: &QString, security: &QString, password: &QString);
        #[qinvokable]
        #[cxx_name = "forgetNetwork"]
        fn forget_network(self: &Network, ssid: &QString);
        #[qinvokable]
        #[cxx_name = "disconnectWifi"]
        fn disconnect_wifi(self: &Network);
        #[qinvokable]
        #[cxx_name = "setAirplaneMode"]
        fn set_airplane_mode(self: &Network, enabled: bool);
        #[qinvokable]
        #[cxx_name = "createHotspot"]
        fn create_hotspot(self: &Network, ssid: &QString, password: &QString);
        #[qinvokable]
        #[cxx_name = "stopHotspot"]
        fn stop_hotspot(self: &Network);
        #[qinvokable]
        #[cxx_name = "isHotspotActive"]
        fn is_hotspot_active(self: &Network) -> bool;
    }

    impl cxx_qt::Threading for Network {}
    impl cxx_qt::Initialize for Network {}
}

use qobject::Network;

const NETWORK: Service = Service("Network");

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
    hotspot_supported: bool,
    hotspot_active: bool,
    airplane_mode_enabled: bool,
    available_networks: QList<QVariant>,
}

impl cxx_qt::Initialize for Network {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), NETWORK, "NetworkError", |obj, (m,): (String,)| obj.network_error(&QString::from(&m)));
        relay(qt.clone(), NETWORK, "ConnectionSuccess", |obj, ()| obj.connection_success());
        relay(qt.clone(), NETWORK, "ConnectionFailed", |obj, (m,): (String,)| obj.connection_failed(&QString::from(&m)));
        mirror(qt, NETWORK, "network", |mut obj, update| {
            let Update::State(s) = update else { return };
            set!(obj, wifi_enabled, wifi_enabled_changed, get(&s, "wifiEnabled"));
            set!(obj, wifi_connected, wifi_connected_changed, get(&s, "wifiConnected"));
            set!(obj, wifi_ssid, wifi_ssid_changed, get(&s, "wifiSsid"));
            set!(obj, wifi_signal_strength, wifi_signal_strength_changed, get(&s, "wifiSignalStrength"));
            set!(obj, ethernet_connected, ethernet_connected_changed, get(&s, "ethernetConnected"));
            set!(obj, ethernet_connection_name, ethernet_connection_name_changed, get(&s, "ethernetConnectionName"));
            set!(obj, wifi_available, wifi_available_changed, get(&s, "wifiAvailable"));
            set!(obj, bluetooth_available, bluetooth_available_changed, get(&s, "bluetoothAvailable"));
            set!(obj, hotspot_supported, hotspot_supported_changed, get(&s, "hotspotSupported"));
            set!(obj, hotspot_active, hotspot_active_changed, get(&s, "hotspotActive"));
            set!(obj, airplane_mode_enabled, airplane_mode_enabled_changed, get(&s, "airplaneModeEnabled"));
            set!(obj, available_networks, available_networks_changed, get(&s, "availableNetworks"));
        });
    }
}

impl Network {
    crate::shell::calls! { NETWORK;
        enable_wifi() => "EnableWifi";
        disable_wifi() => "DisableWifi";
        toggle_wifi() => "ToggleWifi";
        scan_wifi() => "ScanWifi";
        disconnect_wifi() => "DisconnectWifi";
        set_airplane_mode(enabled: bool) => "SetAirplaneMode";
        stop_hotspot() => "StopHotspot";
        connect_to_network(ssid: &QString, password: &QString) => "ConnectToNetwork";
        connect_to_hidden_network(ssid: &QString, security: &QString, password: &QString) => "ConnectToHiddenNetwork";
        forget_network(ssid: &QString) => "ForgetNetwork";
        create_hotspot(ssid: &QString, password: &QString) => "CreateHotspot";
    }
    crate::shell::asks! { NETWORK;
        is_hotspot_active() -> bool => "IsHotspotActive";
    }

}
