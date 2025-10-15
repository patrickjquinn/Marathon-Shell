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
        
        // If this app was waiting to be brought to foreground, do it now
        if (pendingForegroundApp === appId) {
            Logger.info("AppLifecycle", "App registered, applying pending foreground")
            pendingForegroundApp = ""
            bringToForeground(appId)
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
        Logger.info("AppLifecycle", "App in registry: " + (appRegistry[appId] !== undefined))
        
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
            Logger.info("AppLifecycle", "Set foregroundApp to: " + appId)
            
            if (appStates[appId]) {
                appStates[appId].isActive = true
                appStates[appId].lastActiveTime = Date.now()
            }
        } else {
            Logger.warn("AppLifecycle", "App not in registry yet, deferring foreground")
            // App will register itself shortly, set foreground then
            pendingForegroundApp = appId
        }
    }
    
    property string pendingForegroundApp: ""
    
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
        Logger.info("AppLifecycle", "handleSystemBack() called, foregroundApp: " + (foregroundApp ? foregroundApp.appId : "null"))
        
        if (!foregroundApp) {
            Logger.warn("AppLifecycle", "No foreground app to handle back")
            return false
        }
        
        var appId = foregroundApp.appId
        Logger.info("AppLifecycle", "Routing back gesture to: " + appId)
        Logger.info("AppLifecycle", "App registered: " + (appRegistry[appId] !== undefined))
        
        if (appRegistry[appId]) {
            Logger.info("AppLifecycle", "Calling app.handleBack()")
            var handled = appRegistry[appId].handleBack()
            Logger.info("AppLifecycle", "Back handled by app: " + handled)
            return handled
        }
        
        Logger.warn("AppLifecycle", "App not found in registry!")
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
        
        // Clear foreground but keep app alive
        foregroundApp = null
        
        // Add to task switcher
        if (typeof TaskModel !== 'undefined') {
            if (appId === "settings") {
                TaskModel.launchTask("settings", "Settings", "qrc:/images/settings.svg", "marathon", -1)
            } else if (appRegistry[appId]) {
                var app = appRegistry[appId]
                TaskModel.launchTask(
                    app.appId,
                    app.appName,
                    app.appIcon,
                    app.appType || "marathon",
                    app.surfaceId || -1
                )
            }
        }
        
        // Hide the app UI and navigate to task switcher
        if (typeof UIStore !== 'undefined') {
            if (appId === "settings") {
                UIStore.minimizeSettings()
            } else {
                UIStore.minimizeApp()
            }
            
            // Navigate to task switcher
            if (typeof Router !== 'undefined') {
                Router.goToFrames()
            }
        }
        
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

