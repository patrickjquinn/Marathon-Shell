pragma Singleton
import QtQuick

QtObject {
    id: sessionManager

    property bool sessionActive: true
    property bool screenLocked: false
    property bool idleDetectionEnabled: true

    property int idleTimeout: 300000
    property int lockTimeout: 60000
    property double lastActivityTime: 0  // Use double to avoid overflow with Date.now()
    property double idleTime: 0

    property string sessionId: ""
    property string sessionType: "user"
    property string sessionState: "active"

    property bool canLock: true
    property bool canSwitchUser: false
    property bool canLogout: true

    signal sessionLocked
    signal sessionUnlocked
    signal idleStateChanged(bool idle)
    signal userActivityDetected

    function lockSession() {
        console.log("[SessionManager] Locking session...");
        screenLocked = true;
        sessionState = "locked";
        sessionLocked();
        DisplayManager.turnScreenOff();  // Turn off screen when locking
        _platformLock();
    }

    function unlockSession() {
        console.log("[SessionManager] Unlocking session...");
        screenLocked = false;
        sessionState = "active";
        lastActivityTime = Date.now();
        idleTime = 0;

        // Aggressively reset idle timer to prevent immediate re-lock
        idleMonitor.stop();
        idleMonitor.start();

        DisplayManager.turnScreenOn();  // Turn on screen when unlocking
        sessionUnlocked();
        _platformUnlock();
    }

    function logout() {
        console.log("[SessionManager] Logging out...");
        sessionState = "closing";
        _platformLogout();
    }

    function switchUser() {
        if (!canSwitchUser) {
            console.warn("[SessionManager] User switching not available");
            return;
        }

        console.log("[SessionManager] Switching user...");
        _platformSwitchUser();
    }

    function setIdleTimeout(milliseconds) {
        console.log("[SessionManager] Setting idle timeout:", milliseconds);
        idleTimeout = milliseconds;
        _platformSetIdleTimeout(milliseconds);
    }

    function setLockTimeout(milliseconds) {
        console.log("[SessionManager] Setting lock timeout:", milliseconds);
        lockTimeout = milliseconds;
    }

    function reportActivity() {
        lastActivityTime = Date.now();
        idleTime = 0;
        userActivityDetected();
    }

    function inhibitIdle(reason) {
        console.log("[SessionManager] Inhibiting idle:", reason);
        _platformInhibitIdle(reason);
    }

    function uninhibitIdle() {
        console.log("[SessionManager] Uninhibiting idle");
        _platformUninhibitIdle();
    }

    function _platformLock() {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] D-Bus call to systemd-logind Lock");
        } else if (Platform.isMacOS) {
            console.log("[SessionManager] macOS lock screen via CGSession");
        }
    }

    function _platformUnlock() {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] D-Bus call to systemd-logind Unlock");
        }
    }

    function _platformLogout() {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] D-Bus call to systemd-logind Terminate");
        } else if (Platform.isMacOS) {
            console.log("[SessionManager] macOS logout via osascript");
        }
    }

    function _platformSwitchUser() {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] D-Bus call to systemd-logind SwitchTo");
        } else if (Platform.isMacOS) {
            console.log("[SessionManager] macOS fast user switching");
        }
    }

    function _platformSetIdleTimeout(milliseconds) {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] Setting idle timeout via logind IdleAction");
        }
    }

    function _platformInhibitIdle(reason) {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] D-Bus Inhibit idle:", reason);
        }
    }

    function _platformUninhibitIdle() {
        if (Platform.hasSystemdLogind) {
            console.log("[SessionManager] D-Bus Uninhibit");
        }
    }

    function _checkIdleState() {
        var now = Date.now();
        idleTime = now - lastActivityTime;

        var wasIdle = sessionState === "idle";
        var isIdle = idleTime >= idleTimeout;

        if (isIdle && !wasIdle) {
            console.log("[SessionManager] Session is now idle");
            sessionState = "idle";
            idleStateChanged(true);

            if (lockTimeout > 0 && idleTime >= (idleTimeout + lockTimeout)) {
                lockSession();
            }
        } else if (!isIdle && wasIdle) {
            console.log("[SessionManager] Session is now active");
            sessionState = "active";
            idleStateChanged(false);
        }
    }

    property Timer idleMonitor: Timer {
        interval: 5000
        running: idleDetectionEnabled && sessionActive
        repeat: true
        onTriggered: _checkIdleState()
    }

    Component.onCompleted: {
        console.log("[SessionManager] Initialized");
        console.log("[SessionManager] systemd-logind available:", Platform.hasSystemdLogind);

        sessionId = "session-" + Date.now();
        lastActivityTime = Date.now();

        if (Platform.hasSystemdLogind) {
            canSwitchUser = true;
        }
    }
}
