pragma Singleton
import QtQml
QtObject {
    property bool hasQuickPIN: true
    property bool isLockedOut: false
    property int lockoutSecondsRemaining: 0
    property bool fingerprintAvailable: false
    property var attempts: []

    signal authenticationSuccess
    signal authenticationFailed(string reason)
    signal biometricPrompt(string message)
    signal lockoutStateChanged

    function authenticateQuickPIN(pin) { attempts = attempts.concat([pin]); }
    function authenticatePassword(password) { attempts = attempts.concat([password]); }
    function authenticateBiometric(type) {}
}
