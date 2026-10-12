pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property bool muted: false
    property bool speaker: false

    function simulateIncomingCall(number) { log("simulateIncomingCall", number); }
    function simulateCallStateChange(state) { log("simulateCallStateChange", state); }
    function setCallMuted(on) { muted = on; }
    function setSpeakerphone(on) { speaker = on; }
    function isCallMuted() { return muted; }
    function isSpeakerphoneOn() { return speaker; }
}
