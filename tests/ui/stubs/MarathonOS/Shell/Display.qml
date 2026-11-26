pragma Singleton
import QtQml

// As the Rust: every turnScreenOn re-asserts the panel; screenOn changes only on an edge.
QtObject {
    property real dim: 1
    property bool screenOn: true
    property bool nightshade: false
    property bool lightAvailable: true
    property bool rotationAvailable: true
    property bool rotationLocked: false
    property string orientation: "portrait"
    property var offReasons: []
    // E-paper: as display.rs, with what the shell asked of the panel.
    property bool refreshControls: false
    property string refreshMode: "quality"
    property string restingRefreshMode: "quality"
    property bool autoClear: true
    property int fullRefreshes: 0
    property int replacements: 0
    function fullRefresh() {
        fullRefreshes++;
    }
    function contentReplaced() {
        replacements++;
    }
    signal screenStateChanged(bool on)
    function turnScreenOn() {
        screenOn = true;
        screenStateChanged(true);
    }
    function turnScreenOff(reason) {
        offReasons = offReasons.concat([reason]);
        screenOn = false;
        screenStateChanged(false);
    }
    function forceScreenOn() {
        screenOn = true;
        screenStateChanged(true);
        screenOnChanged();
    }
}
