pragma Singleton
import QtQml
// As the Rust: every turnScreenOn re-asserts the panel; screenOn changes only on an edge.
QtObject {
    property bool screenOn: true
    property bool lightAvailable: true
    property var offReasons: []
    signal screenStateChanged(bool on)
    function turnScreenOn() { screenOn = true; screenStateChanged(true); }
    function turnScreenOff(reason) { offReasons = offReasons.concat([reason]); screenOn = false; screenStateChanged(false); }
    function forceScreenOn() { screenOn = true; screenStateChanged(true); screenOnChanged(); }
}
