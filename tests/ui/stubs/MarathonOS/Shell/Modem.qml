pragma Singleton
import QtQml

QtObject {
    property bool modemAvailable: true
    property string callState: "idle"
    property var activeBroadcasts: []
    property string operatorName: ""
    property bool speakerphone: false
    property bool callMuted: false
    function setSpeakerphone(on) {
        speakerphone = on;
    }
    function setCallMuted(muted) {
        callMuted = muted;
    }
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
