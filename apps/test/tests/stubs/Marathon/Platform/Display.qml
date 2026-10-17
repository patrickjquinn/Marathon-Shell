pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property real brightness: 0.5
    property bool autoBrightnessEnabled: false
    property bool lightSensorAvailable: true

    function setScreenState(on) { log("setScreenState", on); }
}
