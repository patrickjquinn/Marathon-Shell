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
    
    // Enable layer rendering for proper ShaderEffectSource capture in task switcher
    layer.enabled: true
    layer.smooth: true
    layer.mipmap: false
    layer.samples: 0
    
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
    property bool canNavigateForward: false
    
    // Content
    property alias content: contentLoader.sourceComponent
    
    // Signals
    signal closed()
    signal minimizeRequested()
    signal backPressed()     // Swipe left/back gesture
    signal forwardPressed()  // Swipe right/forward gesture
    
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
        Logger.info("MApp", appId + " handleBack() called, canNavigateBack: " + canNavigateBack + ", depth: " + navigationDepth)
        
        // If app has navigation depth (internal pages), emit signal for app to handle
        if (canNavigateBack) {
            Logger.info("MApp", appId + " has navigation depth, emitting backPressed signal")
            backPressed()
            return true  // Signal that we handled it
        }
        
        // At root - minimize app (like iOS/Android home button)
        Logger.info("MApp", appId + " at root, minimizing (not closing)")
        minimizeRequested()
        return true  // We handled it (minimize, don't close)
    }
    
    /**
     * Handle system forward gesture (swipe right on nav bar)
     * @returns {bool} - true if handled, false to ignore
     */
    function handleForward() {
        Logger.info("MApp", appId + " handleForward() called, canNavigateForward: " + canNavigateForward)
        
        if (canNavigateForward) {
            Logger.info("MApp", appId + " can navigate forward, emitting forwardPressed signal")
            forwardPressed()
            return true
        }
        
        return false  // Not handled
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
    
    // Store connection for cleanup
    property var minimizeConnection: null
    
    // Lifecycle management
    Component.onCompleted: {
        // Only register with lifecycle manager if NOT in preview mode
        if (appId && !isPreviewMode && typeof AppLifecycleManager !== 'undefined') {
            AppLifecycleManager.registerApp(appId, root)
            Logger.info("MApp", appId + " registered with AppLifecycleManager")
            
            // Connect minimize signal to lifecycle manager (store for cleanup)
            minimizeConnection = minimizeRequested.connect(function() {
                AppLifecycleManager.minimizeForegroundApp()
            })
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
        // Disconnect signals before unregistering
        if (minimizeConnection) {
            minimizeRequested.disconnect(minimizeConnection)
            minimizeConnection = null
        }
        
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

