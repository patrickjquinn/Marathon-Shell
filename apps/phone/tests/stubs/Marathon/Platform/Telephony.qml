pragma Singleton
import QtQml

QtObject {
    property string callState: "idle"
    property string activeNumber: ""
    property bool hasModem: true
    property var log: []

    signal incomingCall(string number)
    signal callFailed(string reason)

    function reset() {
        callState = "idle";
        activeNumber = "";
        hasModem = true;
        log = [];
    }
    function record(entry) {
        log = log.concat([entry]);
    }
    function setState(s) {
        callState = s;
    }
    function dial(number) {
        record("dial:" + number);
        activeNumber = number;
    }
    function dialEmergency(number) {
        record("emergency:" + number);
        activeNumber = number;
    }
    function answer() {
        record("answer");
    }
    function hangup() {
        record("hangup");
    }
    function sendDTMF(digit) {
        record("dtmf:" + digit);
    }
    function setCallMuted(muted) {
        record("mute:" + muted);
    }
    function setSpeakerphone(on) {
        record("speaker:" + on);
    }
}
