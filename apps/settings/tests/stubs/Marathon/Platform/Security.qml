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
    property var calls: []

    signal quickPINChanged
    signal authenticationFailed(string reason)
    signal eraseFailed(string reason)

    function reset() {
        authMode = 0;
        hasQuickPIN = false;
        fingerprintAvailable = false;
        isLockedOut = false;
        failedAttempts = 0;
        canEraseAllContent = false;
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
}
