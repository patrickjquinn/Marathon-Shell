pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property int batteryLevel: 81
    property bool isCharging: true
    property bool isPowerSaveMode: false

    function setPowerSaveMode(on) { log("setPowerSaveMode", on); isPowerSaveMode = on; }
}
