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
    // NetworkManager reports the new state later, as the real client does.
    function toggleWifi() {
        record(["toggleWifi"]);
        const next = !wifiEnabled;
        Qt.callLater(() => wifiEnabled = next);
    }
    function forgetNetwork(ssid) {
        record(["forget", ssid]);
        availableNetworks = availableNetworks.map(n => n.ssid === ssid ? Object.assign({}, n, { known: false }) : n);
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
