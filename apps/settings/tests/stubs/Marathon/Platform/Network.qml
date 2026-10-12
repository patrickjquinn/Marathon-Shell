pragma Singleton
import QtQml

QtObject {
    property bool wifiAvailable: true
    property bool wifiEnabled: true
    property bool wifiConnected: false
    property string wifiSsid: ""
    property int wifiSignalStrength: 0
    property bool airplaneModeEnabled: false
    property var availableNetworks: []
    property var calls: []

    signal connectionSuccess
    signal connectionFailed(string message)

    function reset() {
        wifiAvailable = true;
        wifiEnabled = true;
        wifiConnected = false;
        wifiSsid = "";
        wifiSignalStrength = 0;
        airplaneModeEnabled = false;
        availableNetworks = [];
        calls = [];
    }
    function record(call) {
        calls = calls.concat([call]);
    }
    function toggleWifi() {
        record(["toggleWifi"]);
        wifiEnabled = !wifiEnabled;
    }
    function scanWifi() {
        record(["scanWifi"]);
    }
    function connectToNetwork(ssid, password) {
        record(["connect", ssid, password]);
    }
    function disconnectWifi() {
        record(["disconnect"]);
        wifiConnected = false;
    }
    function setAirplaneMode(on) {
        record(["airplane", on]);
        airplaneModeEnabled = on;
    }
}
