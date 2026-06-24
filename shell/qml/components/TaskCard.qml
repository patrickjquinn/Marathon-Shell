import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: taskCard

    required property int index
    required property string id
    required property string appId
    required property string title
    required property string icon
    required property string type
    required property int surfaceId
    required property var waylandSurface
    property bool haveWayland: false
    property var compositor: null
    property bool taskSwitcherVisible: true
    property bool gridMoving: false
    property bool gridDragging: false
    property bool suppressTapOpen: false
    property Item nativeSurfaceItem: null
    property bool nativeSurfaceActive: false
    property Item registeredSurfaceItem: null
    readonly property bool shouldLoadNativeSurface: taskCard.taskSwitcherVisible && taskCard.haveWayland && typeof taskCard.waylandSurface !== 'undefined' && taskCard.waylandSurface !== null
    // Plain bool, not a derived property binding: Qt's binding-loop detector
    // misfires when 14 TaskCards initialize concurrently with SurfaceRegistry
    // fanning out signals. Updated explicitly from updateRegisteredSurface().
    property bool useRegisteredSurface: false

    signal closed
    signal taskClosed(string appId)

    function refreshNativeSurface() {
        if (!shouldLoadNativeSurface) {
            nativeSurfaceActive = false;
            return;
        }
        nativeSurfaceActive = false;
        Qt.callLater(function () {
            nativeSurfaceActive = shouldLoadNativeSurface;
        });
    }

    function updateRegisteredSurface() {
        if (taskCard.surfaceId <= 0) {
            registeredSurfaceItem = null;
            useRegisteredSurface = false;
            return;
        }
        registeredSurfaceItem = SurfaceRegistry.getSurfaceItem(taskCard.surfaceId);
        useRegisteredSurface = registeredSurfaceItem !== null;
    }

    onWaylandSurfaceChanged: refreshNativeSurface()
    onSurfaceIdChanged: updateRegisteredSurface()
    onTaskSwitcherVisibleChanged: {
        refreshNativeSurface();
        updateRegisteredSurface();
    }
    onHaveWaylandChanged: {
        refreshNativeSurface();
        updateRegisteredSurface();
    }
    Component.onCompleted: {
        refreshNativeSurface();
        updateRegisteredSurface();
    }

    Rectangle {
        id: cardRoot

        property bool closing: false

        anchors.fill: parent
        anchors.margins: 8
        color: MColors.glassTitlebar
        // DS card chrome — 4 px corners. Previously Constants.borderRadiusSharp
        // (=0) made every Active Frames tile a flat box, breaking continuity
        // with the rest of the shell's rounded language.
        radius: MRadius.md
        border.width: 1
        border.color: MColors.borderSubtle
        antialiasing: true
        // Clip children to the rounded corners. Without this, the banner
        // (sharp-cornered Rectangle anchored to the bottom edge) renders
        // its solid fill into the bottom-left/right corner pixels that
        // lie OUTSIDE cardRoot's rounded shape — visually making the
        // handle look wider than the card body.
        clip: true
        scale: closing ? 0.7 : 1
        opacity: closing ? 0 : 1

        SequentialAnimation {
            id: closeAnimation

            ScriptAction {
                script: cardRoot.closing = true
            }

            PauseAnimation {
                duration: 250
            }

            ScriptAction {
                script: {
                    Logger.info("TaskCard", "Closing task: " + taskCard.appId + " type: " + taskCard.type);
                    if (taskCard.type === "native") {
                        if (typeof taskCard.compositor !== 'undefined' && taskCard.compositor && taskCard.surfaceId >= 0) {
                            Logger.info("TaskCard", "Closing native app via compositor, surfaceId: " + taskCard.surfaceId);
                            taskCard.compositor.closeWindow(taskCard.surfaceId);
                        }
                        TaskModel.closeTask(taskCard.id);
                    } else {
                        AppLifecycleManager.closeApp(taskCard.appId);
                    }
                    cardRoot.closing = false;
                }
            }
        }

        MouseArea {
            id: previewTapArea

            property real pressX: 0
            property real pressY: 0
            property real pressTime: 0

            anchors.fill: parent
            anchors.bottomMargin: Math.round(50 * Constants.scaleFactor)
            z: 50
            preventStealing: false
            propagateComposedEvents: true
            onPressed: mouse => {
                pressX = mouse.x;
                pressY = mouse.y;
                pressTime = Date.now();
                mouse.accepted = true;
            }
            onReleased: mouse => {
                var deltaTime = Date.now() - pressTime;
                var deltaX = Math.abs(mouse.x - pressX);
                var deltaY = Math.abs(mouse.y - pressY);
                if (!taskCard.suppressTapOpen && deltaTime < 300 && deltaX < 15 && deltaY < 15) {
                    mouse.accepted = true;
                    Logger.info("TaskCard", "TAP on preview - Opening: " + taskCard.appId);
                    var appId = taskCard.appId;
                    var appTitle = taskCard.title;
                    var appIcon = taskCard.icon;
                    var appType = taskCard.type;
                    Qt.callLater(function () {
                        if (appType !== "native")
                            AppLifecycleManager.restoreApp(appId);
                        else
                            AppLifecycleManager.bringToForeground(appId);
                        UIStore.restoreApp(appId, appTitle, appIcon);
                        taskCard.closed();
                    });
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: cardRoot.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.03)
        }

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: Math.round(50 * Constants.scaleFactor)
                color: MColors.background
                radius: cardRoot.radius

                Loader {
                    id: appPreview

                    anchors.fill: parent
                    anchors.margins: 2
                    active: true
                    asynchronous: true

                    sourceComponent: Item {
                        anchors.fill: parent
                        clip: true
                        enabled: false

                        Item {
                            id: livePreview

                            anchors.fill: parent

                            Item {
                                id: previewContainer

                                property var liveApp: null
                                property string trackedAppId: ""
                                property string watchedAppId: taskCard.appId

                                function updateLiveApp() {
                                    if (trackedAppId !== "" && trackedAppId !== taskCard.appId) {
                                        Logger.info("TaskCard", "DELEGATE RECYCLED: " + trackedAppId + " → " + taskCard.appId);
                                        liveApp = null;
                                    }
                                    trackedAppId = taskCard.appId;
                                    if (taskCard.type === "native") {
                                        liveApp = null;
                                        return;
                                    }
                                    var instance = AppLifecycleManager.getAppInstance(taskCard.appId);
                                    liveApp = instance;
                                    if (liveApp)
                                        snapshotUpdateDebounce.restart();
                                }

                                anchors.fill: parent
                                visible: true
                                clip: true
                                onWatchedAppIdChanged: updateLiveApp()
                                Component.onCompleted: updateLiveApp()
                                onLiveAppChanged: snapshotUpdateDebounce.restart()

                                Timer {
                                    id: snapshotUpdateDebounce

                                    interval: 16
                                    repeat: false
                                    onTriggered: {
                                        if (liveSnapshot.visible)
                                            liveSnapshot.scheduleUpdate();
                                    }
                                }

                                Connections {
                                    function onAppRegistered(appId, instance) {
                                        if (taskCard.type === "native")
                                            return;

                                        if (appId !== taskCard.appId)
                                            return;

                                        previewContainer.liveApp = instance;
                                        snapshotUpdateDebounce.restart();
                                    }

                                    function onAppUnregistered(appId) {
                                        if (appId !== taskCard.appId)
                                            return;

                                        previewContainer.liveApp = null;
                                    }

                                    target: AppLifecycleManager
                                }

                                Connections {
                                    function onTaskSwitcherVisibleChanged() {
                                        if (taskCard.taskSwitcherVisible)
                                            snapshotUpdateDebounce.restart();
                                    }

                                    function onGridMovingChanged() {
                                        if (!taskCard.gridMoving)
                                            snapshotUpdateDebounce.restart();
                                    }

                                    function onGridDraggingChanged() {
                                        if (!taskCard.gridDragging)
                                            snapshotUpdateDebounce.restart();
                                    }

                                    target: taskCard
                                }

                                ShaderEffectSource {
                                    id: liveSnapshot

                                    // App is rendered at full device aspect (W:H = screenWidth:screenHeight).
                                    // The card preview area has its own aspect — fit the app preview INTO it
                                    // letterbox-style, preserving the app's true proportions. The prior
                                    // `width: parent.width; height: (sH/sW)*width` formula always made the
                                    // preview as TALL as the device, which on a 1:2 portrait screen meant
                                    // the rendered texture overflowed the (shorter) card preview area and
                                    // visually clipped the bottom — making the preview look squished + cropped.
                                    property real appAspect: (Constants.screenHeight > 0 && Constants.screenWidth > 0) ? (Constants.screenHeight / Constants.screenWidth) : 1.0
                                    property real parentAspect: (parent.height > 0 && parent.width > 0) ? (parent.height / parent.width) : 1.0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parentAspect >= appAspect ? parent.width : parent.height / appAspect
                                    height: parentAspect >= appAspect ? parent.width * appAspect : parent.height
                                    sourceItem: previewContainer.liveApp
                                    live: false
                                    recursive: true
                                    visible: previewContainer.liveApp !== null
                                    hideSource: false
                                    mipmap: false
                                    smooth: false
                                    format: ShaderEffectSource.RGBA
                                    samples: 0
                                    onVisibleChanged: {
                                        if (visible)
                                            liveSnapshot.scheduleUpdate();
                                    }
                                }

                                Timer {
                                    id: livePreviewRefreshTimer

                                    interval: 200
                                    repeat: true
                                    running: taskCard.taskSwitcherVisible && previewContainer.liveApp !== null && !taskCard.gridMoving && !taskCard.gridDragging
                                    onTriggered: liveSnapshot.scheduleUpdate()
                                }

                                Loader {
                                    id: nativeSurfaceLoader

                                    // Same aspect-preserving fit as liveSnapshot above — without it
                                    // the native (Wayland) surface preview gets stretched/cropped.
                                    property real appAspect: (Constants.screenHeight > 0 && Constants.screenWidth > 0) ? (Constants.screenHeight / Constants.screenWidth) : 1.0
                                    property real parentAspect: (parent.height > 0 && parent.width > 0) ? (parent.height / parent.width) : 1.0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parentAspect >= appAspect ? parent.width : parent.height / appAspect
                                    height: parentAspect >= appAspect ? parent.width * appAspect : parent.height
                                    visible: taskCard.type === "native"
                                    active: taskCard.nativeSurfaceActive && !taskCard.useRegisteredSurface
                                    source: taskCard.haveWayland ? "qrc:/qt/qml/MarathonOS/Shell/qml/components/WaylandShellSurfaceItem.qml" : ""
                                    onItemChanged: {
                                        if (item) {
                                            taskCard.nativeSurfaceItem = item;
                                            taskCard.nativeSurfaceItem.anchors.fill = nativeSurfaceLoader;
                                            item.autoResize = false;
                                            item.hasSentInitialSize = true;
                                            item.isMinimized = true;
                                        } else {
                                            taskCard.nativeSurfaceItem = null;
                                        }
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "surfaceObj"
                                        value: taskCard.waylandSurface
                                        when: taskCard.nativeSurfaceItem !== null
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "surfaceId"
                                        value: taskCard.surfaceId
                                        when: taskCard.nativeSurfaceItem !== null
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "touchEventsEnabled"
                                        value: false
                                        when: taskCard.nativeSurfaceItem !== null
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "inputEventsEnabled"
                                        value: false
                                        when: taskCard.nativeSurfaceItem !== null
                                    }
                                }

                                ShaderEffectSource {
                                    id: registeredSurfacePreview

                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                    sourceItem: taskCard.registeredSurfaceItem
                                    visible: taskCard.useRegisteredSurface
                                    live: true
                                    recursive: true
                                    hideSource: false
                                    smooth: false
                                    format: ShaderEffectSource.RGBA
                                    samples: 0
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                    visible: taskCard.type === "native" && !taskCard.haveWayland
                                    color: MColors.elevated

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Constants.spacingMedium

                                        MAppIcon {
                                            size: Math.round(80 * Constants.scaleFactor)
                                            source: taskCard.icon || "layout-grid"
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Text {
                                            text: taskCard.title || taskCard.appId
                                            color: MColors.textSecondary
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Text {
                                            text: "Native apps not available on macOS"
                                            color: MColors.textTertiary
                                            font.pixelSize: MTypography.sizeXSmall
                                            font.family: MTypography.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                    visible: previewContainer.liveApp === null && (taskCard.type !== "native" || !taskCard.waylandSurface)
                                    color: MColors.background

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Constants.spacingMedium

                                        MAppIcon {
                                            size: Math.round(80 * Constants.scaleFactor)
                                            source: taskCard.icon || "layout-grid"
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Text {
                                            text: taskCard.title || taskCard.appId
                                            color: MColors.textSecondary
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Text {
                                            text: "Preview unavailable"
                                            color: MColors.textTertiary
                                            font.pixelSize: MTypography.sizeXSmall
                                            font.family: MTypography.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: bannerRect

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(50 * Constants.scaleFactor)
            color: MColors.surface
            radius: 0

            MouseArea {
                id: handleTapArea

                property real pressX: 0
                property real pressY: 0
                property real pressTime: 0

                anchors.fill: parent
                z: 50
                preventStealing: false
                propagateComposedEvents: false
                onPressed: mouse => {
                    // Mirror the close button's expanded MouseArea bounds
                    // (anchors.margins: -16) — otherwise this banner-wide tap
                    // area steals taps in the 16 px ring meant to enlarge the
                    // close target.
                    var hitMargin = 16;
                    var p = closeButtonRect.mapToItem(handleTapArea, -hitMargin, -hitMargin);
                    var w = closeButtonRect.width + (hitMargin * 2);
                    var h = closeButtonRect.height + (hitMargin * 2);
                    if (mouse.x >= p.x && mouse.x <= p.x + w && mouse.y >= p.y && mouse.y <= p.y + h) {
                        mouse.accepted = false;
                        return;
                    }
                    pressX = mouse.x;
                    pressY = mouse.y;
                    pressTime = Date.now();
                    mouse.accepted = true;
                }
                onReleased: mouse => {
                    var deltaTime = Date.now() - pressTime;
                    var deltaX = Math.abs(mouse.x - pressX);
                    var deltaY = Math.abs(mouse.y - pressY);
                    if (!taskCard.suppressTapOpen && deltaTime < 300 && deltaX < 15 && deltaY < 15) {
                        mouse.accepted = true;
                        Logger.info("TaskCard", "TAP on handle - Opening: " + taskCard.appId);
                        var appId = taskCard.appId;
                        var appTitle = taskCard.title;
                        var appIcon = taskCard.icon;
                        var appType = taskCard.type;
                        Qt.callLater(function () {
                            if (appType !== "native")
                                AppLifecycleManager.restoreApp(appId);
                            else
                                AppLifecycleManager.bringToForeground(appId);
                            UIStore.restoreApp(appId, appTitle, appIcon);
                            taskCard.closed();
                        });
                    }
                }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingSmall
                anchors.rightMargin: Constants.spacingSmall
                spacing: Constants.spacingSmall

                MAppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: taskCard.icon
                    size: Constants.iconSizeMedium
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Math.round(80 * Constants.scaleFactor)
                    spacing: Math.round(2 * Constants.scaleFactor)

                    Text {
                        text: taskCard.title
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeSmall
                        font.weight: Font.DemiBold
                        font.family: MTypography.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: "Running"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeXSmall
                        font.family: MTypography.fontFamily
                        opacity: 0.7
                    }
                }

                Item {
                    id: closeButtonContainer

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(44 * Constants.scaleFactor)
                    height: Math.round(44 * Constants.scaleFactor)

                    Rectangle {
                        id: closeButtonRect

                        anchors.centerIn: parent
                        width: Math.round(44 * Constants.scaleFactor)
                        height: Math.round(44 * Constants.scaleFactor)
                        radius: MRadius.sm
                        color: closeButtonArea.pressed ? MColors.elevated : MColors.surface
                        scale: closeButtonArea.pressed ? 0.92 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: MMotion.xs
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 80
                                easing.type: Easing.OutCubic
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeXLarge
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: closeButtonArea

                            anchors.fill: parent
                            anchors.margins: -16
                            z: 1000
                            preventStealing: true
                            onPressed: mouse => {
                                taskCard.suppressTapOpen = true;
                                mouse.accepted = true;
                            }
                            onClicked: mouse => {
                                Logger.info("TaskCard", "Closing task via button: " + taskCard.appId);
                                mouse.accepted = true;
                                closeAnimation.start();
                            }
                            onReleased: mouse => {
                                taskCard.suppressTapOpen = false;
                                mouse.accepted = true;
                            }
                            onCanceled: {
                                taskCard.suppressTapOpen = false;
                            }
                        }
                    }
                }
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
    }

    Connections {
        function onSurfaceRegistered(surfaceId) {
            if (surfaceId === taskCard.surfaceId)
                updateRegisteredSurface();
        }

        function onSurfaceUnregistered(surfaceId) {
            if (surfaceId === taskCard.surfaceId)
                updateRegisteredSurface();
        }

        target: SurfaceRegistry
    }

    Behavior on scale {
        enabled: Constants.enableAnimations

        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }
}
