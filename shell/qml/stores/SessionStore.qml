pragma Singleton
import QtQuick

QtObject {
    id: sessionStore

    property bool isLocked: true
    property bool isOnLockScreen: false
    property bool showLockScreen: true
    property bool isAnimatingLock: false
    property string lockTransition: ""
    property real sessionValidUntil: 0
    property Timer lockTimer

    signal lockStateChanging(bool toLocked)
    signal lockStateChanged(bool isLocked)
    signal triggerShakeAnimation
    signal triggerUnlockAnimation

    function lock() {
        console.log("[SessionStore] lock() called - current isLocked:", isLocked, "showLockScreen:", showLockScreen);
        if (isLocked) {
            console.log("[SessionStore] Already locked, ignoring");
            return;
        }
        console.log("[SessionStore] Locking session...");
        showLockScreen = true;
        console.log("[SessionStore] Set showLockScreen to true");
        lockTransition = "locking";
        isAnimatingLock = true;
        lockStateChanging(true);
        lockTimer.interval = 300;
        lockTimer.targetLocked = true;
        lockTimer.restart();
    }

    function unlock() {
        console.log("[SessionStore] unlock() called - current isLocked:", isLocked);
        if (isAnimatingLock && lockTransition === "unlocking") {
            console.log("[SessionStore] Unlock already in progress, ignoring duplicate");
            showLockScreen = false;
            isOnLockScreen = false;
            return;
        }
        if (!isLocked) {
            console.log("[SessionStore] Already unlocked - dismissing lock screen");
            showLockScreen = false;
            isOnLockScreen = false;
            return;
        }
        console.log("[SessionStore] Unlocking session...");
        showLockScreen = false;
        lockTransition = "unlocking";
        isAnimatingLock = true;
        lockStateChanging(false);
        sessionValidUntil = Date.now() + (5 * 60 * 1000);
        console.log("[SessionStore] Grace period set until:", new Date(sessionValidUntil).toLocaleTimeString());
        lockTimer.interval = 300;
        lockTimer.targetLocked = false;
        lockTimer.restart();
    }

    function checkSession() {
        var now = Date.now();
        var isValid = sessionValidUntil > now;
        if (!isValid)
            console.log("[SessionStore] Session expired, PIN required");

        return isValid;
    }

    function showLock() {
        console.log("[SessionStore] Showing lock screen (session may still be unlocked)");
        showLockScreen = true;
    }

    Component.onCompleted: {
        console.log("[SessionStore] Initialized - session locked by default");
    }

    lockTimer: Timer {
        property bool targetLocked: true

        onTriggered: {
            console.log("[SessionStore] Lock transition complete - setting isLocked to:", targetLocked);
            isLocked = targetLocked;
            console.log("[SessionStore] isLocked is now:", isLocked);
            isAnimatingLock = false;
            lockTransition = "";
            lockStateChanged(isLocked);
        }
    }
}
