pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property bool wifiConnected: true
    property string wifiSsid: "Marathon Home"
    property int wifiSignalStrength: 72
    property bool airplaneModeEnabled: false

    function scanWifi() { log("scanWifi"); }
    function setAirplaneMode(on) { log("setAirplaneMode", on); airplaneModeEnabled = on; }
}
