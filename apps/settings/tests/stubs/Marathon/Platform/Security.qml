pragma Singleton
import QtQml

QtObject {
    property int authMode: 0
    property bool hasQuickPIN: false
    property bool fingerprintAvailable: false
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

    function reset() {
        authMode = 0;
        hasQuickPIN = false;
        fingerprintAvailable = false;
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
    function setRemoteConnection(on, password, pin) {
        calls = calls.concat([["remote", on, password, pin]]);
    }
    function currentUsername() {
        return "user";
    }
}
