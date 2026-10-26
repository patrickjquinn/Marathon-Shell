pragma Singleton
import QtQml
QtObject {
    property bool hasQuickPIN: false
    property bool isLockedOut: false
    property int lockoutSecondsRemaining: 0
    property bool fingerprintAvailable: false
    property var attempts: []
    property var firstRunPins: []

    signal authenticationSuccess
    signal authenticationFailed(string reason)
    signal biometricPrompt(string message)
    signal lockoutStateChanged

    function authenticateQuickPIN(pin) { attempts = attempts.concat([pin]); }
    function authenticatePassword(password) { attempts = attempts.concat([password]); }
    function authenticateBiometric(type) {}
    function setQuickPINFirstRun(pin) {
        if (hasQuickPIN)
            return false;
        firstRunPins = firstRunPins.concat([pin]);
        hasQuickPIN = true;
        return true;
    }
}
