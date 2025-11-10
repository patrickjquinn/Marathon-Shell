pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: sessionStore
    
    property bool isLocked: true  // Managed imperatively by signal handlers
    property var lastUnlockTime: null
    property int sessionTimeout: SessionManager.idleTimeout
    
    function unlock() {
        SessionManager.unlockSession()
        isLocked = false
        lastUnlockTime = Date.now()
        Logger.state("SessionStore", "locked", "unlocked")
    }
    
    function lock() {
        SessionManager.lockSession()
        isLocked = true
        // DON'T clear lastUnlockTime - keep it so session can be validated on next unlock
        Logger.state("SessionStore", "unlocked", "locked")
    }
    
    function checkSession() {
        // Check if we have a recent unlock time within the timeout window
        if (lastUnlockTime) {
            var elapsed = Date.now() - lastUnlockTime
            Logger.debug("SessionStore", "Check - elapsed: " + elapsed + "ms, timeout: " + sessionTimeout + "ms")
            if (elapsed <= sessionTimeout) {
                Logger.debug("SessionStore", "Session still valid - no auth required")
                return true
            } else {
                Logger.info("SessionStore", "Session expired after " + elapsed + "ms")
                return false
            }
        }
        Logger.debug("SessionStore", "No unlock timestamp - auth required")
        return false
    }
    
    function resetTimer() {
        if (!isLocked) {
            lastUnlockTime = Date.now()
            SessionManager.reportActivity()
            Logger.debug("SessionStore", "Session timer reset")
        }
    }
    
    function updateLastUnlockTime() {
        lastUnlockTime = Date.now()
        SessionManager.reportActivity()
    }
    
    property Connections sessionManagerConnections: Connections {
        target: SessionManager
        function onSessionLocked() {
            isLocked = true
            // DON'T clear lastUnlockTime - keep it so session can be validated
        }
        function onSessionUnlocked() {
            isLocked = false
            lastUnlockTime = Date.now()
        }
        function onIdleStateChanged(idle) {
            if (idle) {
                Logger.info("SessionStore", "System idle")
            }
        }
    }
    
    Component.onCompleted: {
        console.log("[SessionStore] Initialized with real SessionManager")
        isLocked = true
    }
}
