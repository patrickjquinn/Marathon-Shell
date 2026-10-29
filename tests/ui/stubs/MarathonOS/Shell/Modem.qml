pragma Singleton
import QtQml

QtObject {
    property bool modemAvailable: true
    property string callState: "idle"
    property var activeBroadcasts: []
    signal broadcastReceived(var broadcast)
    function answer() {
        callState = "active";
    }
    function hangup() {
        callState = "idle";
    }
    function acknowledge(path) {
        activeBroadcasts = activeBroadcasts.filter(b => b.path !== path);
    }
}
