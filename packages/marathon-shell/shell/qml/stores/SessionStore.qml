pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: sessionStore
    
    property bool isLocked: SessionManager.screenLocked
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
        lastUnlockTime = null
        Logger.state("SessionStore", "unlocked", "locked")
    }
    
    function checkSession() {
        if (!isLocked && lastUnlockTime) {
            var elapsed = Date.now() - lastUnlockTime
            Logger.debug("SessionStore", "Check - elapsed: " + elapsed + "ms")
            if (elapsed > sessionTimeout) {
                Logger.info("SessionStore", "Session expired")
                lock()
                return false
            }
            Logger.debug("SessionStore", "Session valid")
            return true
        }
        Logger.debug("SessionStore", "No active session")
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
            lastUnlockTime = null
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
