pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

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
    property var appContainer: null
    property var activeDialogs: []
    property bool isClosing: false
    property Component dialogOverlayComponent
    // Open: 0 sits on the icon or card it came from, 1 is in place.
    property real zoom: 1
    property real zoomScaleFrom: 1
    property real zoomXFrom: 0
    property real zoomYFrom: 0
    readonly property real zoomScale: zoomScaleFrom + (1 - zoomScaleFrom) * zoom
    readonly property bool zooming: zoomIn.running

    signal closed
    signal retryRequested(string appId)
    signal minimized

    function _finishNativeCreation(component, id, name, icon, surface, sid) {
        if (!component || appWindow.appId !== id || appWindow.surfaceId !== sid)
            return;

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
                if (nativeInstance.requestClose) {
                    var capturedId = id;
                    nativeInstance.requestClose.connect(function (skipNative) {
                        Logger.info("AppWindow", "Native app requested close: " + capturedId + " skipNative=" + skipNative);
                        appWindow.closeApp(skipNative === true, capturedId);
                    });
                }
                nativeInstance.surfaceSwitched.connect(function () {
                    if (appWindow.appId === id) {
                        appWindow.waylandSurface = nativeInstance.waylandSurface;
                        appWindow.surfaceId = nativeInstance.surfaceId;
                    }
                });
                // Made here with no parent, so nothing else frees it: gone with
                // the app, or each closed app kept its view and last frame.
                const freeWithApp = function (goneId) {
                    if (goneId !== id)
                        return;
                    Tasks.appUnregistered.disconnect(freeWithApp);
                    if (appWindow.appContainer && appWindow.appContainer["appInstance"] === nativeInstance)
                        appWindow.appContainer["appInstance"] = null;
                    nativeInstance.destroy();
                    // Its last window went while on screen: the window goes too.
                    Qt.callLater(function () {
                        if (UIStore.appWindowOpen && UIStore.currentAppId === id && !appWindow.isClosing)
                            appWindow.closeApp(true, id);
                    });
                };
                Tasks.appUnregistered.connect(freeWithApp);
                Logger.info("AppWindow", "Registering native app with lifecycle: " + id);
                AppInstances.register(id, nativeInstance);
                Tasks.bringToForeground(id);
                // Direct connect — a Connections target through the container
                // breaks when the instance is reparented into the switcher.
                if (nativeInstance.revealReadyChanged !== undefined) {
                    var syncReveal = function () {
                        if (nativeInstance.revealReady === true)
                            appWindow.isLoadingComponent = false;
                    };
                    nativeInstance.revealReadyChanged.connect(syncReveal);
                    syncReveal();
                }
                Logger.info("AppWindow", "Native app instance created successfully: " + id);
                appWindow.hasError = false;
            } else {
                appWindow.isLoadingComponent = false;
                Logger.error("AppWindow", "Failed to create native app instance: " + id);
                appWindow.hasError = true;
                appWindow.loadError = qsTr("Something went wrong while starting it.");
            }
        } else if (component.status === Component.Error) {
            appWindow.isLoadingComponent = false;
            Logger.error("AppWindow", "Error loading NativeAppWindow: " + component.errorString());
            appWindow.hasError = true;
            appWindow.loadError = qsTr("Something went wrong while starting it.");
        }
    }

    function show(id, name, icon, type, surface, sid) {
        // A close still animating must not hide or close the app shown now.
        if (slideOut.running) {
            isClosing = false;
            slideOut.stop();
        }
        var hasSurface = (surface !== null && surface !== undefined && sid >= 0);
        if (appWindow.appId === id && hasSurface && appWindow.appContainer && appContentLoader.status === Loader.Ready && appWindow.appContainer["appInstance"] && appWindow.appContainer["appInstance"].visible) {
            // A restore shows the app's own surface again; only another surface is a dialog.
            if (appWindow.waylandSurface !== null && sid !== appWindow.surfaceId && WaylandCompositorManager.compositor.shellSurfaceById(appWindow.surfaceId)) {
                Logger.warn("AppWindow", "Secondary toplevel (dialog) detected for: " + id + " surfaceId " + sid + " (window " + appWindow.surfaceId + ") - creating overlay");
                var dialog = dialogOverlayComponent.createObject(appWindow, {
                    "dialogSurface": surface,
                    "dialogSurfaceId": sid,
                    "ownerAppId": id
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
            appWindow.appContainer["appInstance"].waylandSurface = surface;
            appWindow.appContainer["appInstance"].surfaceId = sid;
            // Backing out minimized it and may have frozen it.
            _unminimize(appWindow.appContainer["appInstance"]);
            Tasks.bringToForeground(id);
            appWindow.visible = true;
            appWindow.focusApp();
            if (appWindow.opacity < 1)
                appWindow.startZoom();

            return;
        }
        if (appWindow.appId === id && hasSurface && appWindow.isLoadingComponent) {
            Logger.info("AppWindow", "Surface arrived for " + id + " (surfaceId: " + sid + ") - creating native window");
            appWindow.waylandSurface = surface;
            appWindow.surfaceId = sid;
            // isLoadingComponent stays true until revealReady — the surface
            // object existing is not the app having rendered.
            var surfComponent = Qt.createComponent("../apps/native/NativeAppWindow.qml", Component.Asynchronous);
            if (surfComponent.status === Component.Ready) {
                _finishNativeCreation(surfComponent, id, name, icon, surface, sid);
            } else {
                var cc = surfComponent, ci = id, cn = name, cic = icon, cs = surface, csid = sid;
                surfComponent.statusChanged.connect(function () {
                    _finishNativeCreation(cc, ci, cn, cic, cs, csid);
                });
            }
            return;
        }
        var launchStartTime = Date.now();
        appId = id;
        appName = name;
        appIcon = icon;
        appType = type || "marathon";
        waylandSurface = surface || null;
        surfaceId = sid || -1;
        hasError = false;
        loadError = "";
        Logger.info("AppWindow", "Showing app window for: " + name + " (type: " + appType + ")");
        if (appWindow.appContainer) {
            if (appWindow.appContainer["children"].length > 0) {
                var currentChild = appWindow.appContainer["children"][0];
                if (currentChild && currentChild.parent) {
                    Logger.info("AppWindow", "Unparenting previous app instance");
                    currentChild.parent = null;
                    currentChild.visible = false;
                }
            }
        }
        if (hasSurface) {
            var existingNativeInstance = AppInstances.get(id);
            if (existingNativeInstance) {
                Logger.info("AppWindow", "Reusing existing app instance: " + id);
                // An instance closed from the switcher while minimized is kept
                // with its dead surface; a relaunch must not show that.
                _rebindSurface(existingNativeInstance, id, surface, sid);
                existingNativeInstance.visible = true;
                // Going home minimized it, which locks its buffer; left set,
                // the restored window showed no new frames.
                _unminimize(existingNativeInstance);
                // A backgrounded app sits in a frozen cgroup. The switcher
                // thaws it through restoreApp(), but a restore that arrives
                // here (home-screen tap, LaunchApp) drew the app's last frame
                // over a process that could not respond to input.
                Tasks.bringToForeground(id);
                appWindow.pendingAppInstance = existingNativeInstance;
                if (appContentLoader.status === Loader.Ready && appWindow.appContainer) {
                    appWindow.appContainer["adoptPendingApp"]();
                } else {
                    suppressSplash = true;
                    appContentLoader.sourceComponent = undefined;
                    appContentLoader.sourceComponent = appInstanceContainer;
                }
            } else {
                Logger.info("AppWindow", "Creating app window with surface for: " + id + " (surfaceId: " + sid + ")");
                appWindow.isLoadingComponent = true;
                var component = Qt.createComponent("../apps/native/NativeAppWindow.qml", Component.Asynchronous);
                if (component.status === Component.Ready) {
                    _finishNativeCreation(component, id, name, icon, surface, sid);
                } else {
                    var capturedComponent = component;
                    var capturedId = id;
                    var capturedName = name;
                    var capturedIcon = icon;
                    var capturedSurface = surface;
                    var capturedSid = sid;
                    component.statusChanged.connect(function () {
                        _finishNativeCreation(capturedComponent, capturedId, capturedName, capturedIcon, capturedSurface, capturedSid);
                    });
                }
            }
        } else {
            Logger.info("AppWindow", "Showing loading splash for: " + id + " - waiting for Wayland surface");
            appWindow.isLoadingComponent = true;
        }
        visible = true;
        focusApp();
        appWindow.startZoom();
        var totalTime = Date.now() - launchStartTime;
        Logger.info("AppWindow", " " + name + " launched in " + totalTime + "ms");
    }

    function detachCurrentApp() {
        Logger.warn("AppWindow", "Detaching current app instance");
        if (appWindow.appContainer && appWindow.appContainer["children"].length > 0) {
            var app = appWindow.appContainer["children"][0];
            if (app) {
                app.parent = null;
                appWindow.appContainer["appInstance"] = null;
                return app;
            }
        }
        return null;
    }

    // Keyboard focus must end on the app's surface, or its window stays inactive and no field can focus.
    function focusApp() {
        forceActiveFocus();
        Qt.callLater(() => {
            var instance = appWindow.appContainer ? appWindow.appContainer["appInstance"] : null;
            if (instance && instance.surfaceItemRef)
                instance.surfaceItemRef.takeFocusForKeyboard();
        });
    }

    function hide() {
        appContentLoader.source = "";
        isClosing = false;
        slideOut.start();
    }

    function closeApp(skipNativeClose, appIdOverride) {
        var targetAppId = (appIdOverride !== undefined && appIdOverride !== null && appIdOverride !== "") ? appIdOverride : appId;
        if (targetAppId === "")
            return;

        Tasks.closeApp(targetAppId, skipNativeClose === true);
        if (targetAppId !== appId)
            return;

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

    // Scale + translate from the launch origin: the surface keeps its size.
    function startZoom() {
        var origin = WindowOrigins.takeLaunch();
        var r = origin && parent && width > 0 ? parent.mapFromItem(null, origin.rect.x, origin.rect.y, origin.rect.width, origin.rect.height) : null;
        if (r && r.width > 0) {
            zoomScaleFrom = r.width / width;
            zoomXFrom = r.x - x;
            // A card shows the app's top; an icon is the middle of the window it becomes.
            zoomYFrom = (origin.fromCard ? r.y : r.y + (r.height - height * zoomScaleFrom) / 2) - y;
        } else {
            zoomScaleFrom = 0.92;
            zoomXFrom = width * (1 - zoomScaleFrom) / 2;
            zoomYFrom = height * (1 - zoomScaleFrom) / 2;
        }
        zoomIn.restart();
    }

    function _unminimize(instance) {
        if (instance.isMinimized !== undefined)
            instance.isMinimized = false;
    }

    function _rebindSurface(instance, id, surface, sid) {
        if (instance.surfaceId !== sid) {
            Logger.warn("AppWindow", "Rebinding " + id + " from surfaceId " + instance.surfaceId + " to " + sid);
            instance.waylandSurface = surface;
            instance.surfaceId = sid;
        }
    }

    function reattachInstance(instance, id, name, icon, type) {
        Logger.warn("AppWindow", "Re-attaching detached instance: " + id);
        _unminimize(instance);

        appWindow.appId = id;
        appWindow.appName = name;
        appWindow.appIcon = icon;
        appWindow.appType = type;
        UIStore.restoreApp(id, name, icon);

        if (!appContentLoader.item) {
            appWindow.pendingAppInstance = instance;
            appContentLoader.source = "appInstanceContainer";
            appContentLoader.sourceComponent = appInstanceContainer;
        } else {
            instance.parent = appWindow.appContainer;
            instance.anchors.fill = appWindow.appContainer;
            appWindow.appContainer["appInstance"] = instance;
        }
        instance.visible = true;
        appWindow.visible = true;
        appWindow.focusApp();
        appWindow.startZoom();
        Logger.info("AppWindow", "Instance re-attached successfully: " + id);
    }

    color: MColors.surface
    focus: true
    transform: [
        Scale {
            xScale: appWindow.zoomScale
            yScale: appWindow.zoomScale
        },
        Translate {
            x: appWindow.zoomXFrom * (1 - appWindow.zoom)
            y: appWindow.zoomYFrom * (1 - appWindow.zoom)
        }
    ]
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            console.log("[AppWindow] Back/Escape key pressed");
            hide();
            event.accepted = true;
        }
    }

    // Watchdog (the time Android takes to boot not counted): if the splash
    // sits for 20 s without a surface arriving
    // (X11-only app on a Wayland-only stack, runner crash before
    // attaching, missing flatpak runtime, etc.), surface the error
    // state so the user isn't trapped on a forever-loading screen.
    Timer {
        id: launchTimeout

        interval: 20000
        repeat: false
        running: appWindow.isLoadingComponent && !appWindow.hasError && !Tasks.androidStarting
        onTriggered: {
            Logger.warn("AppWindow", "Launch timeout for " + appWindow.appId + " — no surface after 20 s");
            appWindow.isLoadingComponent = false;
            appWindow.hasError = true;
            appWindow.loadError = qsTr("It didn't respond in time.");
        }
    }

    // The launch splash: the app's icon on the ambience.
    Rectangle {
        id: loadingSplash

        readonly property bool showing: appWindow.isLoadingComponent && !appWindow.hasError && !(appWindow.waylandSurface && appContentLoader.status === Loader.Ready && appWindow.appContainer && appWindow.appContainer["appInstance"] && appWindow.appContainer["appInstance"].revealReady === true)

        anchors.fill: parent
        color: "black"
        // Cross-fades into the app's first frame.
        opacity: showing ? 1 : 0
        visible: opacity > 0
        z: 1000

        KeelAmbienceBackground {
            anchors.fill: parent
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
            brightest: AmbienceService.brightest
            darkest: AmbienceService.darkest
        }

        Column {
            // Same size on screen as the launcher icon it grew from, and
            // pulsing until the app shows its first frame.
            scale: splashPulse.value / appWindow.zoomScale
            anchors.centerIn: parent
            spacing: Silica.Theme.paddingLarge

            MAppIcon {
                id: splashIconImage

                loadAsync: false
                size: Silica.Theme.iconSizeLauncher
                source: appWindow.appIcon || ""
                anchors.horizontalCenter: parent.horizontalCenter
                visible: source !== "" && (status === Image.Ready || !isImage)
                onStatusChanged: {
                    if (status === Image.Ready)
                        Logger.debug("AppWindow", "Splash icon loaded: " + source + " intrinsic: " + implicitWidth + "x" + implicitHeight);
                    else if (status === Image.Error)
                        Logger.warn("AppWindow", "Failed to load splash icon: " + source);
                }
            }

            GlyphIcon {
                name: "grid-3x3"
                size: Silica.Theme.iconSizeLauncher
                color: Silica.Theme.secondaryColor
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !splashIconImage.visible
            }

            Silica.BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: Silica.BusyIndicatorSize.Small
                running: loadingSplash.showing && slowLaunch.fired
                opacity: running ? 1 : 0
            }
        }

        // The pulse gives up after 5 s and the busy indicator takes over.
        Timer {
            id: slowLaunch

            property bool fired: false

            interval: 5000
            running: loadingSplash.showing
            onRunningChanged: if (running)
                fired = false
            onTriggered: fired = true
        }

        SequentialAnimation {
            id: splashPulse

            property real value: 1

            running: loadingSplash.showing && !slowLaunch.fired && !MMotion.reduceMotion
            loops: Animation.Infinite
            onRunningChanged: if (!running)
                value = 1

            NumberAnimation {
                target: splashPulse
                property: "value"
                to: 1.08
                duration: MMotion.durationFor("pulse") / 2
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: splashPulse
                property: "value"
                to: 1
                duration: MMotion.durationFor("pulse") / 2
                easing.type: Easing.InOutSine
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.durationFor("nav")
                easing.type: Easing.InOutQuad
            }
        }
    }

    // An app that failed to open: a Silica placeholder on the ambience.
    Rectangle {
        id: errorState

        anchors.fill: parent
        color: "black"
        visible: appWindow.hasError
        z: 1001

        KeelAmbienceBackground {
            anchors.fill: parent
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
            brightest: AmbienceService.brightest
            darkest: AmbienceService.darkest
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Silica.Theme.horizontalPageMargin
            spacing: Silica.Theme.paddingLarge

            Silica.InfoLabel {
                width: parent.width
                text: qsTr("%1 couldn't open").arg(appWindow.appName || qsTr("The app"))
            }

            Silica.Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: (appWindow.loadError ? appWindow.loadError + " " : "") + qsTr("Try again. If it keeps happening, restart your phone.")
                color: Silica.Theme.secondaryHighlightColor
            }

            Silica.Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Try again")
                onClicked: {
                    const id = appWindow.appId;
                    appWindow.hide();
                    appWindow.retryRequested(id);
                }
            }

            Silica.Button {
                anchors.horizontalCenter: parent.horizontalCenter
                //: Button that closes the app's error screen
                text: qsTr("Close")
                backgroundColor: "transparent"
                onClicked: appWindow.hide()
            }
        }
    }

    ParallelAnimation {
        id: zoomIn

        NumberAnimation {
            target: appWindow
            property: "zoom"
            from: 0
            to: 1
            duration: MMotion.dur(MMotion.slow)
            easing.type: Easing.Bezier
            easing.bezierCurve: MMotion.easingDecelerateCurve
        }
        NumberAnimation {
            target: appWindow
            property: "opacity"
            from: 0
            to: 1
            duration: MMotion.dur(MMotion.slow) / 2
            easing.type: Easing.OutQuad
        }
    }

    ParallelAnimation {
        id: slideOut

        NumberAnimation {
            target: appWindow
            property: "opacity"
            from: 1
            to: 0
            duration: MMotion.durationFor("nav")
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: appWindow
            property: "scale"
            from: 1.0
            to: 0.96
            duration: MMotion.durationFor("nav")
            easing.type: Easing.InCubic
        }
        onFinished: {
            appWindow.visible = false;
            appWindow.scale = 1.0;
            if (appWindow.isClosing) {
                appWindow.isClosing = false;
                appWindow.closed();
            }
        }
    }

    Component {
        id: appInstanceContainer

        Item {
            id: containerRoot

            property var appInstance: null
            property var registerConnection: null
            property var unregisterConnection: null
            property var minimizeConnection: null
            property var closedConnection: null

            function disconnectApp() {
                if (!appInstance)
                    return;
                if (registerConnection && appInstance.requestRegister)
                    appInstance.requestRegister.disconnect(containerRoot, registerConnection);
                if (unregisterConnection && appInstance.requestUnregister)
                    appInstance.requestUnregister.disconnect(containerRoot, unregisterConnection);
                if (minimizeConnection && appInstance.minimizeRequested)
                    appInstance.minimizeRequested.disconnect(containerRoot, minimizeConnection);
                if (closedConnection && appInstance.closed)
                    appInstance.closed.disconnect(containerRoot, closedConnection);
                registerConnection = null;
                unregisterConnection = null;
                minimizeConnection = null;
                closedConnection = null;
            }

            function adoptPendingApp() {
                if (appWindow.pendingAppInstance) {
                    disconnectApp();
                    appInstance = appWindow.pendingAppInstance;
                    appWindow.pendingAppInstance = null;
                    appInstance.parent = containerRoot;
                    appInstance.anchors.fill = containerRoot;
                    var capturedAppName = appWindow.appName;
                    var capturedAppId = appWindow.appId;
                    var capturedWindow = appWindow;
                    if (appInstance.requestRegister) {
                        registerConnection = function (appId, appInst) {
                            console.log("AppWindow: App requested registration:", appId);
                            AppInstances.register(appId, appInst);
                        };
                        appInstance.requestRegister.connect(containerRoot, registerConnection);
                    }

                    if (appInstance.requestUnregister) {
                        unregisterConnection = function (appId) {
                            console.log("AppWindow: App requested unregistration:", appId);
                            AppInstances.unregister(appId);
                        };
                        appInstance.requestUnregister.connect(containerRoot, unregisterConnection);
                    }

                    if (appInstance.minimizeRequested) {
                        minimizeConnection = function () {
                            Logger.info("AppWindow", "MApp minimize requested: " + capturedAppName);
                            if (capturedWindow)
                                capturedWindow.minimized();
                        };
                        appInstance.minimizeRequested.connect(containerRoot, minimizeConnection);
                    }

                    if (appInstance.closed) {
                        closedConnection = function () {
                            Logger.info("AppWindow", "MApp closed: " + capturedAppName);
                            if (capturedWindow)
                                capturedWindow.hide();
                        };
                        appInstance.closed.connect(containerRoot, closedConnection);
                    }

                    Logger.info("AppWindow", "MApp instance connected: " + capturedAppId);
                }
            }

            anchors.fill: parent
            Component.onCompleted: {
                adoptPendingApp();
            }
            Component.onDestruction: disconnectApp()
        }
    }

    Loader {
        id: appContentLoader

        anchors.fill: parent
        asynchronous: true
        visible: status === Loader.Ready && item !== null
        opacity: status === Loader.Ready ? 1 : 0
        onItemChanged: appWindow.appContainer = item
        onStatusChanged: {
            if (status === Loader.Error) {
                Logger.error("AppWindow", "Failed to load app content for: " + appWindow.appId);
                appWindow.hasError = true;
                appWindow.loadError = qsTr("Its files couldn't be loaded.");
                appWindow.isLoadingComponent = false;
            } else if (status === Loader.Ready) {
                Logger.info("AppWindow", "App content loaded successfully for: " + appWindow.appId);
                splashHideTimer.start();
                appWindow.suppressSplash = false;
            } else if (status === Loader.Loading) {
                if (!appWindow.suppressSplash)
                    appWindow.isLoadingComponent = true;
                else
                    Logger.info("AppWindow", "Splash suppressed for reload of: " + appWindow.appId);
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
        onTriggered: {}
    }

    dialogOverlayComponent: Component {
        WaylandShellSurfaceItem {
            id: dialogItem

            property var dialogSurface: null
            property int dialogSurfaceId: -1
            property string ownerAppId

            z: 1000
            // Once its surface is gone the item paints an opaque placeholder,
            // which would black out every app shown after it.
            visible: hasFirstFrame && ownerAppId === appWindow.appId
            surfaceObj: dialogSurface
            surfaceId: dialogSurfaceId
            shellSurface: (dialogSurface && dialogSurface.xdgSurface) ? dialogSurface.xdgSurface : null
            hasSentInitialSize: true
            autoResize: true
            Component.onCompleted: {
                Logger.info("DialogOverlay", "Created dialog overlay for surfaceId: " + dialogSurfaceId);
            }

            // The surface's own destroyed() never came: this item's view keeps
            // the QWaylandSurface alive until the item goes.
            onSurfaceDestroyed: {
                Logger.warn("DialogOverlay", "Dialog surface destroyed: " + dialogSurfaceId);
                appWindow.activeDialogs = appWindow.activeDialogs.filter(d => d !== dialogItem);
                dialogItem.destroy();
            }
        }
    }
}
