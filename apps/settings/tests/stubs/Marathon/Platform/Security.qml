pragma Singleton
import QtQml

QtObject {
    property bool hasTrackpadCombo: false
    property bool recordingCombo: false
    property string recordedCombo: ""
    signal trackpadComboSaved
    function setTrackpadCombo(combo, pin) {
    }
    function recordTrackpadCombo(on) {
    }

    property int authMode: 0
    property bool hasQuickPIN: false
    property bool fingerprintAvailable: false
    property bool hasFingerprintReader: false
    property var enrolledFingers: []
    property int fingerprintStages: 0
    property string fingerprintScanType: "press"
    property string fingerprintBlocked: ""
    property bool isLockedOut: false
    property int lockoutSecondsRemaining: 0
    property int failedAttempts: 0
    property bool canEraseAllContent: false
    property string dataEncryption: "none"
    property string remoteConnection: "unavailable"
    property var calls: []

    signal quickPINChanged
    signal authenticationFailed(string reason)
    signal eraseFailed(string reason)
    signal remoteConnectionApplied
    signal remoteConnectionFailed(string reason)
    signal bugReportCreated(string path)
    signal bugReportFailed(string reason)
    signal fingerprintEnrollStatus(string result, int passed, int stages)
    signal fingerprintEnrolled(string finger)
    signal fingerprintDeleted(string finger)
    signal fingerprintFailed(string reason)

    function reset() {
        authMode = 0;
        hasQuickPIN = false;
        fingerprintAvailable = false;
        hasFingerprintReader = false;
        enrolledFingers = [];
        fingerprintStages = 0;
        fingerprintScanType = "press";
        fingerprintBlocked = "";
        isLockedOut = false;
        failedAttempts = 0;
        canEraseAllContent = false;
        dataEncryption = "none";
        remoteConnection = "unavailable";
        calls = [];
    }
    function setQuickPIN(pin, password) {
        calls = calls.concat([["set", pin, password]]);
    }
    function removeQuickPIN(password) {
        calls = calls.concat([["remove", password]]);
    }
    function eraseAllContent(secret) {
        calls = calls.concat([["erase", secret]]);
    }
    function wifiPassword(ssid, secret) {
        calls = calls.concat([["wifiPassword", ssid, secret]]);
        return secret === "1234" ? "hunter22" : "";
    }
    function setRemoteConnection(on, password, pin) {
        calls = calls.concat([["remote", on, password, pin]]);
    }
    function createBugReport() {
        calls = calls.concat([["bugReport"]]);
    }
    function enrollFingerprint(finger, pin) {
        calls = calls.concat([["enroll", finger, pin]]);
    }
    function cancelFingerprintEnroll() {
        calls = calls.concat([["cancelEnroll"]]);
    }
    function deleteFingerprint(finger, pin) {
        calls = calls.concat([["deleteFinger", finger, pin]]);
    }
    function currentUsername() {
        return "user";
    }
}
