pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property bool available: true
    property int ambientLight: 120
    property bool proximityNear: false
}
