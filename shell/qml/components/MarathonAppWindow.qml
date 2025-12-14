import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: appWindow

    property string appId: ""
    property string appName: ""
    property string appIcon: ""
    property string appType: "marathon"
    property var waylandSurface: null
    property int surfaceId: -1
    property var pendingAppInstance: null
    property bool isLoadingComponent: false
    property string loadError: ""
    property bool hasError: false
    property bool suppressSplash: false
    // Track active dialog overlays to ensure cleanup
    property var activeDialogs: []
    // Track whether we're actually closing (vs just hiding for minimize)
    property bool isClosing: false
    // Component for creating floating dialog overlays (file pickers, etc.)
    // These are xdg_toplevel windows that should float above the main app
    property Component dialogOverlayComponent

    dialogOverlayComponent: Component {
        WaylandShellSurfaceItem {
            id: dialogItem

            property var dialogSurface: null
            property int dialogSurfaceId: -1

            // Fill the app window for maximized dialogs (mobile UX)
            anchors.fill: parent
            z: 1000
            // Bind to the dialog surface
            surfaceObj: dialogSurface
            surfaceId: dialogSurfaceId
            shellSurface: dialogSurface ? dialogSurface.xdgSurface : null
            // Dialogs should be visible immediately
            hasSentInitialSize: true
            autoResize: true
            Component.onCompleted: {
                Logger.info("DialogOverlay", "Created dialog overlay for surfaceId: " + dialogSurfaceId);
            }

            // Destroy when the surface is destroyed
            Connections {
                function onSurfaceDestroyed() {
                    Logger.info("DialogOverlay", "Dialog surface destroyed: " + dialogSurfaceId);
                    dialogItem.destroy();
                }

                target: dialogSurface
            }
        }
    }

    signal closed
    signal minimized

    function show(id, name, icon, type, surface, sid) {

        // FAST PATH: Seamlessly update surface for active, visible native app
        // This prevents unparenting/reloading which causes flickering/splash screen
        // CRITICAL: Only use fast path if the appInstance is actually present and visible
        // After minimize, appInstance is detached/null so we must fall through to reload
        if (appWindow.appId === id && type === "native" && appContentLoader.item && appContentLoader.status === Loader.Ready && appContentLoader.item.appInstance && appContentLoader.item.appInstance.visible) {
            // Handle secondary surfaces (file dialogs, etc.) - don't ignore them!
            // File dialogs in GTK are xdg_toplevels, not popups, so autoCreatePopupItems won't handle them
            if (appWindow.waylandSurface !== null && appWindow.waylandSurface !== surface && surface !== null) {
                Logger.info("AppWindow", "Secondary toplevel (dialog) detected for: " + id + " - creating overlay");
                // Create a floating dialog overlay for the secondary surface
                var dialog = dialogOverlayComponent.createObject(appWindow, {
                    "dialogSurface": surface,
                    "dialogSurfaceId": sid
                });
                if (dialog) {
                    activeDialogs.push(dialog);
                    Logger.info("AppWindow", "Dialog overlay created for surfaceId: " + sid);
                }
                return;
            }
            Logger.info("AppWindow", "Seamlessly updating surface for active app: " + id);
            appWindow.waylandSurface = surface;
            appWindow.surfaceId = sid;
            // Update the inner instance directly
            appContentLoader.item.appInstance.waylandSurface = surface;
            appContentLoader.item.appInstance.surfaceId = sid;
            // Ensure visibility and focus state
            appWindow.visible = true;
            appWindow.forceActiveFocus();
            if (appWindow.opacity < 1)
                slideIn.start();

            return;
        }
        var launchStartTime = Date.now(); // Performance measurement
        console.log("=============== SHOW() CALLED ===============");
        console.log("  id:", id);
        console.log("  name:", name);
        console.log("  type:", type);
        console.log("  surface:", surface);
        console.log("  sid:", sid);
        appId = id;
        appName = name;
        appIcon = icon;
        appType = type || "marathon";
        waylandSurface = surface || null;
        surfaceId = sid || -1;
        hasError = false;
        loadError = "";
        console.log("  appType set to:", appType);
        Logger.info("AppWindow", "Showing app window for: " + name + " (type: " + appType + ")");
        // CRITICAL: Cleanup connections and unparent the current app instance BEFORE switching
        if (appContentLoader.item) {
            // Trigger cleanup in the container's onDestruction
            // This will disconnect signals before unparenting
            if (appContentLoader.item.children.length > 0) {
                var currentChild = appContentLoader.item.children[0];
                if (currentChild && currentChild.parent) {
                    Logger.info("AppWindow", "Unparenting previous app instance");
                    currentChild.parent = null;
                    currentChild.visible = false;
                }
            }
        }
        if (appType === "native") {
            // Check if native app instance already exists in lifecycle manager
            var existingNativeInstance = null;
            if (typeof AppLifecycleManager !== 'undefined')
                existingNativeInstance = AppLifecycleManager.getAppInstance(id);

            if (existingNativeInstance) {
                // Reuse existing native app instance - just reparent it
                console.log("[NATIVE APP] Reusing existing instance:", id);
                Logger.info("AppWindow", "Reusing existing native app instance: " + id);
                existingNativeInstance.visible = true;
                appWindow.pendingAppInstance = existingNativeInstance;
                existingNativeInstance.visible = true;
                appWindow.pendingAppInstance = existingNativeInstance;
                // OPTIMIZATON: If loader is already ready, simply adopt the instance
                // to avoid destroying/recreating the container (prevents blank flash)
                if (appContentLoader.status === Loader.Ready && appContentLoader.item) {
                    appContentLoader.item.adoptPendingApp();
                } else {
                    // Force reload if loader is not ready or empty
                    suppressSplash = true;
                    appContentLoader.sourceComponent = undefined;
                    appContentLoader.sourceComponent = appInstanceContainer;
                }
            } else {
                // Create new native app instance using dynamic loading
                console.log("[NATIVE APP] Creating new instance:", id);
                Logger.info("AppWindow", "Creating new native app instance: " + id);
                appWindow.isLoadingComponent = true;
                Logger.info("AppWindow", "Showing loading splash...");
                var component = Qt.createComponent("../apps/native/NativeAppWindow.qml", Component.Asynchronous);

                function finishCreation() {
                    if (component.status === Component.Ready) {
                        var nativeInstance = component.createObject(null, {
                            "nativeAppId": id,
                            "nativeTitle": name,
                            "nativeAppIcon": icon,
                            "waylandSurface": surface,
                            "surfaceId": sid
                        });
                        if (nativeInstance) {
                            appWindow.pendingAppInstance = nativeInstance;
                            appContentLoader.sourceComponent = undefined;
                            appContentLoader.sourceComponent = appInstanceContainer;
                            appWindow.isLoadingComponent = false;
                            // Connect close request signal
                            if (nativeInstance.requestClose) {
                                // CRITICAL: Capture `id` in closure scope - do NOT use appWindow.appId
                                // because appWindow.appId may have changed to a different app!
                                var capturedId = id;
                                nativeInstance.requestClose.connect(function (skipNative) {
                                    Logger.info("AppWindow", "Native app requested close: " + capturedId + " skipNative=" + skipNative);
                                    appWindow.closeApp(skipNative === true);
                                });
                            }

                            // CRITICAL: Register native app with lifecycle manager so it can be minimized/restored
                            if (typeof AppLifecycleManager !== 'undefined') {
                                Logger.info("AppWindow", "Registering native app with lifecycle: " + id);
                                AppLifecycleManager.registerApp(id, nativeInstance);
                                AppLifecycleManager.bringToForeground(id);
                            }
                            Logger.info("AppWindow", "Native app instance created successfully: " + id);
                            appWindow.hasError = false;
                        } else {
                            appWindow.isLoadingComponent = false;
                            Logger.error("AppWindow", "Failed to create native app instance: " + id);
                            appWindow.hasError = true;
                            appWindow.loadError = "Failed to create native app instance.";
                        }
                    } else if (component.status === Component.Error) {
                        appWindow.isLoadingComponent = false;
                        Logger.error("AppWindow", "Error loading NativeAppWindow: " + component.errorString());
                        appWindow.hasError = true;
                        appWindow.loadError = component.errorString();
                    }
                }

                if (component.status === Component.Ready)
                    finishCreation();
                else
                    component.statusChanged.connect(finishCreation);
            }
        } else {
            // Check if app exists in registry
            var appInfo = MarathonAppRegistry.getApp(id);
            if (appInfo && appInfo.absolutePath && appInfo.entryPoint) {
                // Check if app instance already exists in lifecycle manager
                var existingInstance = null;
                if (typeof AppLifecycleManager !== 'undefined')
                    existingInstance = AppLifecycleManager.getAppInstance(id);

                if (existingInstance) {
                    // Reuse existing instance - just reparent it
                    Logger.info("AppWindow", "Reusing existing app instance: " + id);
                    console.log("AppWindow: Reusing and re-registering existing instance:", id);
                    // Re-register to ensure it's in foreground state
                    if (typeof AppLifecycleManager !== 'undefined')
                        AppLifecycleManager.registerApp(id, existingInstance);

                    existingInstance.visible = true;
                    appWindow.pendingAppInstance = existingInstance;
                    existingInstance.visible = true;
                    appWindow.pendingAppInstance = existingInstance;
                    // OPTIMIZATON: If loader is already ready, simply adopt the instance
                    if (appContentLoader.status === Loader.Ready && appContentLoader.item) {
                        appContentLoader.item.adoptPendingApp();
                    } else {
                        // Force reload
                        appContentLoader.sourceComponent = undefined;
                        appContentLoader.sourceComponent = appInstanceContainer;
                    }
                } else {
                    // Load external Marathon app asynchronously
                    Logger.info("AppWindow", "Loading external app from: " + appInfo.absolutePath);
                    console.log("[DEBUG] MarathonAppLoader exists:", typeof MarathonAppLoader !== 'undefined');
                    console.log("[DEBUG] MarathonAppLoader value:", MarathonAppLoader);
                    // Show loading splash while component loads
                    appWindow.isLoadingComponent = true;
                    // Use async loading to avoid blocking UI
                    if (typeof MarathonAppLoader !== 'undefined' && MarathonAppLoader !== null) {
                        console.log("[DEBUG] Calling MarathonAppLoader.loadAppAsync for:", id);
                        MarathonAppLoader.loadAppAsync(id);
                    } else {
                        console.error("[ERROR] MarathonAppLoader is not available!");
                        appWindow.hasError = true;
                        appWindow.loadError = "MarathonAppLoader not available";
                        appWindow.isLoadingComponent = false;
                    }
                }
            } else {
                // Load placeholder template app
                Logger.info("AppWindow", "Loading template app for: " + id);
                appContentLoader.setSource("../apps/template/TemplateApp.qml", {
                    "_appId": id,
                    "_appName": name,
                    "_appIcon": icon
                });
            }
        }
        visible = true;
        forceActiveFocus();
        slideIn.start();
        // Performance logging - measure total time to visible
        var totalTime = Date.now() - launchStartTime;
        Logger.info("AppWindow", " " + name + " launched in " + totalTime + "ms");
    }

    function detachCurrentApp() {
        Logger.info("AppWindow", "Detaching current app instance");
        if (appContentLoader.item && appContentLoader.item.children.length > 0) {
            var app = appContentLoader.item.children[0];
            if (app) {
                app.parent = null;
                // CRITICAL: Clear the appInstance reference so fast path doesn't trigger on restore
                // Without this, the fast path condition (appContentLoader.item.appInstance.visible)
                // still passes and we just update surface instead of reloading the content
                appContentLoader.item.appInstance = null;
                return app;
            }
        }
        return null;
    }

    function hide() {
        // Just hide the window (for minimize) - don't emit closed()
        appContentLoader.source = "";
        isClosing = false;
        slideOut.start();
    }

    // Call this when actually closing the app (user explicitly closes, not minimize)
    function closeApp(skipNativeClose) {
        // Ensure lifecycle manager knows the app is fully closed (removes task)
        // skipNativeClose: true if closed by "X" button native (surface already gone)
        // skipNativeClose: false if closed by shell UI (task switcher/gesture)
        if (typeof AppLifecycleManager !== 'undefined')
            AppLifecycleManager.closeApp(appId, skipNativeClose === true);

        // CRITICAL: Cleanup any active dialog overlays (file pickers, etc.)
        // If we don't do this, they remain attached to the surface which causes
        // a crash when the client destroys the surface after we request close.
        if (activeDialogs.length > 0) {
            Logger.info("AppWindow", "Cleaning up " + activeDialogs.length + " dialog overlays");
            for (var i = 0; i < activeDialogs.length; i++) {
                if (activeDialogs[i])
                    activeDialogs[i].destroy();
            }
            activeDialogs = [];
        }
        UIStore.closeApp();
        appContentLoader.source = "";
        isClosing = true;
        slideOut.start();
    }

    // Re-attach a detached native app instance from backgroundAppsContainer
    // This is used when restoring an app whose surface was destroyed during minimize
    function reattachInstance(instance, id, name, icon, type) {
        Logger.info("AppWindow", "Re-attaching detached instance: " + id);
        // CRITICAL: Reset isMinimized FIRST to unlock the buffer and allow new frames
        if (instance.isMinimized !== undefined)
            instance.isMinimized = false;

        // Set app window properties
        appWindow.appId = id;
        appWindow.appName = name;
        appWindow.appIcon = icon;
        appWindow.appType = type;
        // CRITICAL: Update UIStore so shell knows an app is open
        // Without this, subsequent minimize gestures won't run the minimize flow
        if (typeof UIStore !== 'undefined') {
            UIStore.appWindowOpen = true;
            UIStore.currentAppId = id;
            UIStore.currentAppName = name;
            UIStore.currentAppIcon = icon;
        }
        // Load the container component if needed
        if (!appContentLoader.item) {
            appWindow.pendingAppInstance = instance;
            appContentLoader.source = "appInstanceContainer";
            appContentLoader.sourceComponent = appInstanceContainer;
        } else {
            // Re-parent the instance to the existing container
            instance.parent = appContentLoader.item;
            instance.anchors.fill = appContentLoader.item;
            appContentLoader.item.appInstance = instance;
        }
        instance.visible = true;
        appWindow.visible = true;
        appWindow.forceActiveFocus();
        slideIn.start();
        Logger.info("AppWindow", "Instance re-attached successfully: " + id);
    }

    anchors.fill: parent
    color: MColors.surface
    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            console.log("[AppWindow] Back/Escape key pressed");
            MarathonAppLoader.unloadApp(appId);
            hide();
            event.accepted = true;
        }
    }
    // Loading splash (shown while component is loading)
    Rectangle {
        id: loadingSplash

        anchors.fill: parent
        color: MColors.background
        visible: appWindow.isLoadingComponent && !appWindow.hasError
        z: 1000

        Column {
            anchors.centerIn: parent
            spacing: 24

            // High-quality app icon with proper scaling
            Image {
                id: splashIconImage

                width: Math.round(128 * Constants.scaleFactor)
                height: width
                source: appWindow.appIcon && appWindow.appIcon.startsWith("file://") ? appWindow.appIcon : ""
                anchors.horizontalCenter: parent.horizontalCenter
                smooth: true
                mipmap: true
                sourceSize.width: 256 // Request high-res and downscale for crispness
                sourceSize.height: 256
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                visible: source !== "" && status === Image.Ready
                onStatusChanged: {
                    if (status === Image.Ready)
                        Logger.debug("AppWindow", "Splash icon loaded: " + source + " intrinsic: " + implicitWidth + "x" + implicitHeight);
                    else if (status === Image.Error)
                        Logger.warn("AppWindow", "Failed to load splash icon: " + source);
                }
            }

            // Fallback icon when no file path is available or image failed to load
            Icon {
                name: "grid-3x3"
                size: Math.round(128 * Constants.scaleFactor)
                color: MColors.textTertiary
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !splashIconImage.visible
            }

            Text {
                text: "Loading " + (appWindow.appName || "app") + "..."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Error state (shown when app fails to load)
    Rectangle {
        id: errorState

        anchors.fill: parent
        color: MColors.background
        visible: appWindow.hasError
        z: 1001

        Column {
            anchors.centerIn: parent
            spacing: 24
            width: parent.width * 0.8

            Icon {
                name: "alert-triangle"
                size: 80
                color: MColors.error
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Failed to Launch"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.DemiBold
                font.family: MTypography.fontFamily
                color: MColors.textPrimary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: appWindow.appName + " failed to start.\n\n" + (appWindow.loadError || "Unknown error occurred.")
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            MButton {
                text: "Close"
                variant: "primary"
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: {
                    appWindow.hide();
                }
            }
        }
    }

    NumberAnimation {
        id: slideIn

        target: appWindow
        property: "opacity"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut

        target: appWindow
        property: "opacity"
        from: 1
        to: 0
        duration: 300
        easing.type: Easing.InCubic
        onFinished: {
            appWindow.visible = false;
            // Only emit closed() if we're actually closing, not just hiding for minimize
            if (appWindow.isClosing) {
                appWindow.isClosing = false;
                closed();
            }
        }
    }

    Component {
        id: appInstanceContainer

        Item {
            id: containerRoot

            property var appInstance: null
            property var minimizeConnection: null
            property var closedConnection: null

            function adoptPendingApp() {
                if (appWindow.pendingAppInstance) {
                    appInstance = appWindow.pendingAppInstance;
                    appWindow.pendingAppInstance = null;
                    appInstance.parent = containerRoot;
                    appInstance.anchors.fill = containerRoot;
                    // Capture values to avoid accessing potentially destroyed appWindow later
                    var capturedAppName = appWindow.appName;
                    var capturedAppId = appWindow.appId;
                    var capturedWindow = appWindow; // Capture window reference
                    // Connect to app registration signals
                    // NOTE: Explicitly specify 'appInstanceContainer' as receiver to avoid "Could not find receiver" warnings
                    if (appInstance.requestRegister)
                        appInstance.requestRegister.connect(containerRoot, function (appId, appInst) {
                            console.log("AppWindow: App requested registration:", appId);
                            if (typeof AppLifecycleManager !== 'undefined')
                                AppLifecycleManager.registerApp(appId, appInst);
                            else
                                console.error("AppWindow: AppLifecycleManager not available!");
                        });

                    if (appInstance.requestUnregister)
                        appInstance.requestUnregister.connect(containerRoot, function (appId) {
                            console.log("AppWindow: App requested unregistration:", appId);
                            if (typeof AppLifecycleManager !== 'undefined')
                                AppLifecycleManager.unregisterApp(appId);
                        });

                    if (appInstance.minimizeRequested)
                        minimizeConnection = appInstance.minimizeRequested.connect(containerRoot, function () {
                            Logger.info("AppWindow", "MApp minimize requested: " + capturedAppName);
                            if (capturedWindow)
                                capturedWindow.minimized();
                        });

                    if (appInstance.closed)
                        closedConnection = appInstance.closed.connect(containerRoot, function () {
                            Logger.info("AppWindow", "MApp closed: " + capturedAppName);
                            if (capturedWindow)
                                capturedWindow.hide();
                        });

                    Logger.info("AppWindow", "MApp instance connected: " + capturedAppId);
                }
            }

            anchors.fill: parent
            Component.onCompleted: {
                adoptPendingApp();
            }
            Component.onDestruction: {
                if (appInstance) {
                    if (minimizeConnection && appInstance.minimizeRequested)
                        appInstance.minimizeRequested.disconnect(minimizeConnection);

                    if (closedConnection && appInstance.closed)
                        appInstance.closed.disconnect(closedConnection);
                }
            }
        }
    }

    Loader {
        id: appContentLoader

        anchors.fill: parent
        asynchronous: true // OPTIMIZATION: Re-enabled async loading to prevent UI freeze
        visible: status === Loader.Ready && item !== null
        opacity: status === Loader.Ready ? 1 : 0
        onStatusChanged: {
            if (status === Loader.Error) {
                Logger.error("AppWindow", "Failed to load app content for: " + appId);
                appWindow.hasError = true;
                appWindow.loadError = "Failed to load app content";
                appWindow.isLoadingComponent = false;
            } else if (status === Loader.Ready) {
                Logger.info("AppWindow", "App content loaded successfully for: " + appId);
                // Delay hiding splash slightly to ensure smooth transition
                splashHideTimer.start();
                appWindow.suppressSplash = false;
            } else if (status === Loader.Loading) {
                if (!appWindow.suppressSplash)
                    appWindow.isLoadingComponent = true;
                else
                    Logger.info("AppWindow", "Splash suppressed for reload of: " + appId);
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }

    Timer {
        id: splashHideTimer

        interval: 100
        onTriggered: {
            appWindow.isLoadingComponent = false;
        }
    }

    Connections {
        function onAppLoadProgress(appId, percent) {
            if (appId === appWindow.appId)
                Logger.debug("AppWindow", "Load progress for " + appId + ": " + percent + "%");
        }

        function onAppInstanceReady(appId, instance) {
            if (appId === appWindow.appId) {
                Logger.info("AppWindow", "App instance ready: " + appId);
                // IMMEDIATELY register the app with AppLifecycleManager
                if (typeof AppLifecycleManager !== 'undefined') {
                    console.log("AppWindow: Registering app:", appId);
                    AppLifecycleManager.registerApp(appId, instance);
                } else {
                    console.error("AppWindow: AppLifecycleManager not available!");
                }
                // Store instance and set component - container will pick it up
                appWindow.pendingAppInstance = instance;
                // FORCE reload by clearing first
                appContentLoader.sourceComponent = undefined;
                appContentLoader.sourceComponent = appInstanceContainer;
                Logger.info("AppWindow", "External app loaded successfully: " + appId);
                appWindow.hasError = false;
                appWindow.isLoadingComponent = false;
            }
        }

        function onLoadError(appId, error) {
            if (appId === appWindow.appId) {
                Logger.error("AppWindow", "Received loadError signal for: " + appId + " - " + error);
                appWindow.hasError = true;
                appWindow.loadError = error;
                appWindow.isLoadingComponent = false;
            }
        }

        target: MarathonAppLoader
        enabled: MarathonAppLoader !== null
    }
}
