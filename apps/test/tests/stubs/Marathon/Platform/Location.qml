pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property bool active: false
    property real latitude: 53.349805
    property real longitude: -6.26031
    property real accuracy: 12

    function start() { log("start"); active = true; }
    function stop() { log("stop"); active = false; }
}
