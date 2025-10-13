pragma Singleton
import QtQuick
import MarathonOS.Shell

/**
 * AppLifecycleManager - Centralized app lifecycle management
 * 
 * Responsibilities:
 * - Track running apps and their state
 * - Handle app lifecycle events (launch, pause, resume, close)
 * - Manage app stack (foreground, background)
 * - Route system events to apps (back gesture, minimize, etc.)
 * - Coordinate with UIStore and TaskManagerStore
 */
QtObject {
    id: lifecycleManager
    
    // Current foreground app
    property var foregroundApp: null
    
    // App registry (appId -> app instance)
    property var appRegistry: ({})
    
    // App state (appId -> state object)
    property var appStates: ({})
    
    /**
     * Register an app instance
     * Called automatically by MApp on creation
     */
    function registerApp(appId, appInstance) {
        Logger.info("AppLifecycle", "Registering app: " + appId)
        appRegistry[appId] = appInstance
        
        if (!appStates[appId]) {
            appStates[appId] = {
                appId: appId,
                isActive: false,
                isPaused: false,
                isMinimized: false,
                launchTime: Date.now(),
                lastActiveTime: 0
            }
        }
    }
    
    /**
     * Unregister an app instance
     */
    function unregisterApp(appId) {
        Logger.info("AppLifecycle", "Unregistering app: " + appId)
        delete appRegistry[appId]
        delete appStates[appId]
    }
    
    /**
     * Bring app to foreground
     */
    function bringToForeground(appId) {
        Logger.info("AppLifecycle", "Bringing to foreground: " + appId)
        
        // Pause current foreground app
        if (foregroundApp && foregroundApp.appId !== appId) {
            if (appRegistry[foregroundApp.appId]) {
                var previousApp = appRegistry[foregroundApp.appId]
                previousApp.pause()
                previousApp.stop()  // No longer visible
            }
        }
        
        // Resume/start new foreground app
        if (appRegistry[appId]) {
            var app = appRegistry[appId]
            app.start()   // Becomes visible
            app.resume()  // Becomes active
            foregroundApp = { appId: appId }
            
            if (appStates[appId]) {
                appStates[appId].isActive = true
                appStates[appId].lastActiveTime = Date.now()
            }
        }
    }
    
    /**
     * Restore app from task switcher
     */
    function restoreApp(appId) {
        Logger.info("AppLifecycle", "Restoring app: " + appId)
        
        if (appRegistry[appId]) {
            appRegistry[appId].restore()  // Calls start() + resume()
            bringToForeground(appId)
        }
    }
    
    /**
     * Handle system back gesture
     * Routes to current foreground app
     * @returns {bool} - true if handled, false to close app
     */
    function handleSystemBack() {
        if (!foregroundApp) {
            Logger.debug("AppLifecycle", "No foreground app to handle back")
            return false
        }
        
        var appId = foregroundApp.appId
        Logger.info("AppLifecycle", "Routing back gesture to: " + appId)
        
        if (appRegistry[appId]) {
            var handled = appRegistry[appId].handleBack()
            Logger.debug("AppLifecycle", "Back handled by app: " + handled)
            return handled
        }
        
        return false
    }
    
    /**
     * Minimize current foreground app
     */
    function minimizeForegroundApp() {
        if (!foregroundApp) {
            return false
        }
        
        var appId = foregroundApp.appId
        Logger.info("AppLifecycle", "Minimizing app: " + appId)
        
        if (appRegistry[appId]) {
            appRegistry[appId].minimize()  // Calls pause() and emits appMinimized
            appRegistry[appId].stop()      // No longer visible
            
            if (appStates[appId]) {
                appStates[appId].isMinimized = true
                appStates[appId].isActive = false
            }
        }
        
        foregroundApp = null
        return true
    }
    
    /**
     * Broadcast low memory warning to all apps
     */
    function broadcastLowMemory() {
        Logger.warn("AppLifecycle", "Broadcasting low memory warning to all apps")
        
        for (var appId in appRegistry) {
            if (appRegistry[appId]) {
                appRegistry[appId].handleLowMemory()
            }
        }
    }
    
    /**
     * Close an app
     */
    function closeApp(appId) {
        Logger.info("AppLifecycle", "Closing app: " + appId)
        
        if (appRegistry[appId]) {
            appRegistry[appId].close()
        }
        
        if (foregroundApp && foregroundApp.appId === appId) {
            foregroundApp = null
        }
        
        unregisterApp(appId)
    }
    
    /**
     * Get app state
     */
    function getAppState(appId) {
        return appStates[appId] || null
    }
    
    /**
     * Check if app is running
     */
    function isAppRunning(appId) {
        return appRegistry.hasOwnProperty(appId)
    }
    
    /**
     * Get current foreground app ID
     */
    function getForegroundAppId() {
        return foregroundApp ? foregroundApp.appId : null
    }
}

