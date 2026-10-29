pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property real volume: 0.4
    property string audioProfile: "normal"

    function setAudioProfile(p) {
        log("setAudioProfile", p);
        audioProfile = p;
    }
    function playRingtone() {
        log("playRingtone");
    }
    function stopRingtone() {
        log("stopRingtone");
    }
    function playNotificationSound() {
        log("playNotificationSound");
    }
    function playAlarmSound() {
        log("playAlarmSound");
    }
    function stopAlarmSound() {
        log("stopAlarmSound");
    }
    function vibratePattern(pattern) {
        log("vibratePattern", pattern);
    }
}
