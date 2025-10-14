import QtQuick
import MarathonOS.Shell

/**
 * MApp - Base app lifecycle container
 * 
 * All Marathon apps should inherit from this to get:
 * - Lifecycle management (onAppPaused, onAppResumed, onAppDestroyed)
 * - Navigation stack support
 * - Back gesture handling
 * - Safe area management
 * - State preservation
 * 
 * Usage:
 *   MApp {
 *       id: myApp
 *       appId: "my-app"
 *       appName: "My App"
 *       
 *       onBackPressed: {
 *           // Handle back navigation
 *           // Return true if handled, false to close app
 *           if (canGoBack()) {
 *               goBack()
 *               return true
 *           }
 *           return false
 *       }
 *       
 *       content: Item {
 *           // Your app content here
 *       }
 *   }
 */
Item {
    id: root
    
    // App metadata
    property string appId: ""
    property string appName: ""
    property string appIcon: ""
    
    // Preview mode - when true, this is just a visual preview (TaskSwitcher)
    // and should NOT register with AppLifecycleManager
    property bool isPreviewMode: false
    
    // Lifecycle state
    property bool isActive: false
    property bool isPaused: false
    property bool isMinimized: false
    property bool isVisible: false
    property bool isForeground: false
    
    // Navigation
    property int navigationDepth: 0
    property bool canNavigateBack: navigationDepth > 0
    
    // Content
    property alias content: contentLoader.sourceComponent
    
    // Signals
    signal closed()
    signal minimizeRequested()
    signal backPressed()  // Return true to handle, false to close app
    
    // Lifecycle signals (aligned with Android/iOS)
    signal appCreated()       // onCreate (Android) / didFinishLaunching (iOS)
    signal appLaunched()      // App fully initialized and ready
    signal appStarted()       // onStart (Android) / willEnterForeground (iOS)
    signal appResumed()       // onResume (Android) / didBecomeActive (iOS)
    signal appPaused()        // onPause (Android) / willResignActive (iOS)
    signal appStopped()       // onStop (Android) / didEnterBackground (iOS)
    signal appMinimized()     // App minimized to task switcher
    signal appRestored()      // App restored from task switcher
    signal appWillTerminate() // About to be destroyed
    signal appClosed()        // onDestroy (Android) / willTerminate (iOS)
    
    // Visibility events
    signal appBecameVisible()
    signal appBecameHidden()
    
    // Memory warnings
    signal lowMemoryWarning()
    
    /**
     * Handle system back gesture
     * Override this in your app to provide custom back behavior
     * @returns {bool} - true if handled, false to close app
     */
    function handleBack() {
        // Emit signal for app to handle
        backPressed()
        
        // If not handled by app, default is to close
        return false
    }
    
    /**
     * Start app (becomes visible)
     */
    function start() {
        if (!isVisible) {
            isVisible = true
            appStarted()
            Logger.debug("MApp", appId + " started (visible)")
        }
    }
    
    /**
     * Stop app (no longer visible)
     */
    function stop() {
        if (isVisible) {
            isVisible = false
            appStopped()
            Logger.debug("MApp", appId + " stopped (hidden)")
        }
    }
    
    /**
     * Pause app (when minimized or another app takes focus)
     */
    function pause() {
        if (!isPaused) {
            isPaused = true
            isActive = false
            isForeground = false
            appPaused()
            Logger.debug("MApp", appId + " paused")
        }
    }
    
    /**
     * Resume app (when restored from minimized or regains focus)
     */
    function resume() {
        if (isPaused || !isActive) {
            isPaused = false
            isActive = true
            isForeground = true
            appResumed()
            Logger.debug("MApp", appId + " resumed")
        }
    }
    
    /**
     * Minimize app (user gesture)
     */
    function minimize() {
        isMinimized = true
        pause()
        appMinimized()
        minimizeRequested()
        Logger.debug("MApp", appId + " minimized")
    }
    
    /**
     * Restore app from minimized state
     */
    function restore() {
        isMinimized = false
        resume()
        start()
        appRestored()
        Logger.debug("MApp", appId + " restored")
    }
    
    /**
     * Close app completely
     */
    function close() {
        appWillTerminate()
        stop()
        appClosed()
        closed()
        Logger.debug("MApp", appId + " closed")
    }
    
    /**
     * Notify app of low memory
     */
    function handleLowMemory() {
        lowMemoryWarning()
        Logger.warn("MApp", appId + " received low memory warning")
    }
    
    // Content area
    Item {
        anchors.fill: parent
        
        Loader {
            id: contentLoader
            anchors.fill: parent
        }
    }
    
    // Lifecycle management
    Component.onCompleted: {
        // Only register with lifecycle manager if NOT in preview mode
        if (appId && !isPreviewMode && typeof AppLifecycleManager !== 'undefined') {
            AppLifecycleManager.registerApp(appId, root)
            Logger.info("MApp", appId + " registered with AppLifecycleManager")
        }
        
        appCreated()
        isActive = true
        isVisible = true
        isForeground = true
        appLaunched()
        appStarted()
        appResumed()
        
        if (appId && !isPreviewMode) {
            Logger.info("MApp", appId + " lifecycle: created → launched → started → resumed")
        }
    }
    
    Component.onDestruction: {
        // Only unregister if NOT in preview mode
        if (appId && !isPreviewMode && typeof AppLifecycleManager !== 'undefined') {
            AppLifecycleManager.unregisterApp(appId)
        }
        
        appWillTerminate()
        appClosed()
        
        if (appId && !isPreviewMode) {
            Logger.info("MApp", appId + " destroyed")
        }
    }
    
    // Monitor visibility changes
    onIsVisibleChanged: {
        if (isVisible) {
            appBecameVisible()
        } else {
            appBecameHidden()
        }
    }
}

