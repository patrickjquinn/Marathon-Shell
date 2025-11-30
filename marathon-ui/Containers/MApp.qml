import QtQuick

Item {
    id: root

    property string appId: ""
    property string appName: ""
    property string appIcon: ""

    property bool isPreviewMode: false
    property bool debugLifecycle: false

    property bool isActive: false
    property bool isPaused: false
    property bool isMinimized: false
    property bool isVisible: false
    property bool isForeground: false

    property int navigationDepth: 0
    property bool canNavigateBack: navigationDepth > 0
    property bool canNavigateForward: false

    property alias content: contentLoader.sourceComponent

    signal closed
    signal minimizeRequested
    signal backPressed
    signal forwardPressed

    signal appCreated
    signal appLaunched
    signal appStarted
    signal appResumed
    signal appPaused
    signal appStopped
    signal appMinimized
    signal appRestored
    signal appWillTerminate
    signal appClosed

    signal appBecameVisible
    signal appBecameHidden

    signal lowMemoryWarning

    function handleBack() {
        if (canNavigateBack) {
            backPressed();
            return true;
        }

        minimizeRequested();
        return true;
    }

    function handleForward() {
        if (canNavigateForward) {
            forwardPressed();
            return true;
        }

        return false;
    }

    function start() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "start()");
        if (!isVisible) {
            isVisible = true;
            appStarted();
        }
    }

    function stop() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "stop()");
        if (isVisible) {
            isVisible = false;
            appStopped();
        }
    }

    function pause() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "pause()");
        if (!isPaused) {
            isPaused = true;
            isActive = false;
            isForeground = false;
            appPaused();
        }
    }

    function resume() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "resume()");
        if (isPaused || !isActive) {
            isPaused = false;
            isActive = true;
            isForeground = true;
            appResumed();
        }
    }

    function minimize() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "minimize()");
        isMinimized = true;
        pause();
        appMinimized();
    }

    function restore() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "restore()");
        isMinimized = false;
        resume();
        start();
        appRestored();
    }

    function close() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "close()");
        appWillTerminate();
        stop();
        appClosed();
        closed();
    }

    function handleLowMemory() {
        if (debugLifecycle)
            console.log("[MApp Lifecycle]", appId, "handleLowMemory()");
        lowMemoryWarning();
    }

    Item {
        anchors.fill: parent

        Loader {
            id: contentLoader
            anchors.fill: parent
        }
    }

    // Signal emitted when app wants to register with lifecycle manager
    signal requestRegister(string appId, var appInstance)
    signal requestUnregister(string appId)

    Component.onCompleted: {
        console.log("━━━━━━━ MApp.onCompleted FIRED ━━━━━━━");
        console.log("  appId:", appId);
        console.log("  appName:", appName);
        console.log("  appIcon:", appIcon);
        console.log("  AppLifecycleManager defined:", typeof AppLifecycleManager !== 'undefined');

        appCreated();
        isActive = true;
        isVisible = true;
        isForeground = true;
        appLaunched();
        appStarted();
        appResumed();

        // Try direct registration first (works in shell context)
        if (typeof AppLifecycleManager !== 'undefined' && appId) {
            console.log("   Calling AppLifecycleManager.registerApp() directly");
            AppLifecycleManager.registerApp(appId, root);
        } else {
            // Fallback: emit signal for external registration (works in app loader context)
            console.log("  ℹ  AppLifecycleManager not available, emitting requestRegister signal");
            requestRegister(appId, root);
        }
        console.log("━━━━━━━ MApp.onCompleted COMPLETE ━━━━━━━");
    }

    Component.onDestruction: {
        appWillTerminate();
        appClosed();

        // Try direct unregistration first
        if (typeof AppLifecycleManager !== 'undefined' && appId) {
            AppLifecycleManager.unregisterApp(appId);
        } else {
            // Fallback: emit signal
            requestUnregister(appId);
        }
    }

    onIsVisibleChanged: {
        if (isVisible) {
            appBecameVisible();
        } else {
            appBecameHidden();
        }
    }
}
