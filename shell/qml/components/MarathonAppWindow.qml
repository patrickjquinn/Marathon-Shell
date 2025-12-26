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
    property var activeDialogs: []
    property bool isClosing: false
    property Component dialogOverlayComponent

    signal closed
    signal minimized

    function show(id, name, icon, type, surface, sid) {
        function finishCreation() {
            if (!component)
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
                    appWindow.isLoadingComponent = false;
                    if (nativeInstance.requestClose) {
                        var capturedId = id;
                        nativeInstance.requestClose.connect(function (skipNative) {
                            Logger.info("AppWindow", "Native app requested close: " + capturedId + " skipNative=" + skipNative);
                            appWindow.closeApp(skipNative === true, capturedId);
                        });
                    }
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

        var component = null;
        if (appWindow.appId === id && type === "native" && appContentLoader.item && appContentLoader.status === Loader.Ready && appContentLoader.item.appInstance && appContentLoader.item.appInstance.visible) {
            if (appWindow.waylandSurface !== null && appWindow.waylandSurface !== surface && surface !== null) {
                Logger.info("AppWindow", "Secondary toplevel (dialog) detected for: " + id + " - creating overlay");
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
            appContentLoader.item.appInstance.waylandSurface = surface;
            appContentLoader.item.appInstance.surfaceId = sid;
            appWindow.visible = true;
            appWindow.forceActiveFocus();
            if (appWindow.opacity < 1)
                slideIn.start();

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
        if (appContentLoader.item) {
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
            var existingNativeInstance = null;
            if (typeof AppLifecycleManager !== 'undefined')
                existingNativeInstance = AppLifecycleManager.getAppInstance(id);

            if (existingNativeInstance) {
                Logger.info("AppWindow", "Reusing existing native app instance: " + id);
                existingNativeInstance.visible = true;
                appWindow.pendingAppInstance = existingNativeInstance;
                if (appContentLoader.status === Loader.Ready && appContentLoader.item) {
                    appContentLoader.item.adoptPendingApp();
                } else {
                    suppressSplash = true;
                    appContentLoader.sourceComponent = undefined;
                    appContentLoader.sourceComponent = appInstanceContainer;
                }
            } else {
                Logger.info("AppWindow", "Creating new native app instance: " + id);
                appWindow.isLoadingComponent = true;
                Logger.info("AppWindow", "Showing loading splash...");
                component = Qt.createComponent("../apps/native/NativeAppWindow.qml", Component.Asynchronous);
                if (component.status === Component.Ready)
                    finishCreation();
                else
                    component.statusChanged.connect(finishCreation);
            }
        } else {
            Logger.warn("AppWindow", "Non-native show() requested for appId=" + id + " - waiting for Wayland surface");
            appWindow.isLoadingComponent = true;
        }
        visible = true;
        forceActiveFocus();
        slideIn.start();
        var totalTime = Date.now() - launchStartTime;
        Logger.info("AppWindow", " " + name + " launched in " + totalTime + "ms");
    }

    function detachCurrentApp() {
        Logger.info("AppWindow", "Detaching current app instance");
        if (appContentLoader.item && appContentLoader.item.children.length > 0) {
            var app = appContentLoader.item.children[0];
            if (app) {
                app.parent = null;
                appContentLoader.item.appInstance = null;
                return app;
            }
        }
        return null;
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

        if (typeof AppLifecycleManager !== 'undefined')
            AppLifecycleManager.closeApp(targetAppId, skipNativeClose === true);

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

    function reattachInstance(instance, id, name, icon, type) {
        Logger.info("AppWindow", "Re-attaching detached instance: " + id);
        if (instance.isMinimized !== undefined)
            instance.isMinimized = false;

        appWindow.appId = id;
        appWindow.appName = name;
        appWindow.appIcon = icon;
        appWindow.appType = type;
        if (typeof UIStore !== 'undefined') {
            UIStore.appWindowOpen = true;
            UIStore.currentAppId = id;
            UIStore.currentAppName = name;
            UIStore.currentAppIcon = icon;
        }
        if (!appContentLoader.item) {
            appWindow.pendingAppInstance = instance;
            appContentLoader.source = "appInstanceContainer";
            appContentLoader.sourceComponent = appInstanceContainer;
        } else {
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
            hide();
            event.accepted = true;
        }
    }

    Rectangle {
        id: loadingSplash

        anchors.fill: parent
        color: MColors.background
        visible: appWindow.isLoadingComponent && !appWindow.hasError && !(appContentLoader.status === Loader.Ready && appContentLoader.item && appContentLoader.item.appInstance && appContentLoader.item.appInstance.revealReady === true)
        z: 1000

        Column {
            anchors.centerIn: parent
            spacing: 24

            Image {
                id: splashIconImage

                width: Math.round(128 * Constants.scaleFactor)
                height: width
                source: appWindow.appIcon && appWindow.appIcon.startsWith("file://") ? appWindow.appIcon : ""
                anchors.horizontalCenter: parent.horizontalCenter
                smooth: true
                mipmap: true
                sourceSize.width: 256
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
                    var capturedAppName = appWindow.appName;
                    var capturedAppId = appWindow.appId;
                    var capturedWindow = appWindow;
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
        asynchronous: true
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
        onTriggered: {}
    }

    dialogOverlayComponent: Component {
        WaylandShellSurfaceItem {
            id: dialogItem

            property var dialogSurface: null
            property int dialogSurfaceId: -1

            anchors.fill: parent
            z: 1000
            surfaceObj: dialogSurface
            surfaceId: dialogSurfaceId
            shellSurface: (dialogSurface && dialogSurface.xdgSurface) ? dialogSurface.xdgSurface : null
            hasSentInitialSize: true
            autoResize: true
            Component.onCompleted: {
                Logger.info("DialogOverlay", "Created dialog overlay for surfaceId: " + dialogSurfaceId);
            }

            Connections {
                function onDestroyed() {
                    Logger.info("DialogOverlay", "Dialog surface destroyed: " + dialogSurfaceId);
                    dialogItem.destroy();
                }

                target: dialogSurface
            }
        }
    }
}
