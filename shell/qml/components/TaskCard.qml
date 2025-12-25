import MarathonOS.Shell
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

    signal closed
    signal taskClosed(string appId)

    Rectangle {
        id: cardRoot

        property bool closing: false

        anchors.fill: parent
        anchors.margins: 8
        color: MColors.glassTitlebar
        radius: Constants.borderRadiusSharp
        border.width: Constants.borderWidthThin
        border.color: MColors.borderSubtle
        antialiasing: Constants.enableAntialiasing
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
                        if (typeof AppLifecycleManager !== 'undefined')
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
                        if (typeof AppLifecycleManager !== 'undefined') {
                            if (appType !== "native")
                                AppLifecycleManager.restoreApp(appId);
                            else
                                AppLifecycleManager.bringToForeground(appId);
                        }
                        UIStore.restoreApp(appId, appTitle, appIcon);
                        taskCard.closed();
                    });
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
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
                radius: parent.parent.radius

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
                                    if (typeof AppLifecycleManager === 'undefined') {
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

                                // Debounced snapshot refresh (avoid spamming scheduleUpdate)
                                Timer {
                                    id: snapshotUpdateDebounce

                                    interval: 16
                                    repeat: false
                                    onTriggered: {
                                        if (liveSnapshot.visible)
                                            liveSnapshot.scheduleUpdate();
                                    }
                                }

                                // Prefer signal-based registration over polling.
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

                                    target: typeof AppLifecycleManager !== "undefined" ? AppLifecycleManager : null
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

                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                    sourceItem: previewContainer.liveApp
                                    // Snapshot-based preview: avoid live recursive rendering per-card.
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

                                // Throttled live updates: keep previews feeling alive without per-frame cost.
                                Timer {
                                    id: livePreviewRefreshTimer

                                    interval: 200
                                    repeat: true
                                    running: taskCard.taskSwitcherVisible && previewContainer.liveApp !== null && !taskCard.gridMoving && !taskCard.gridDragging
                                    onTriggered: liveSnapshot.scheduleUpdate()
                                }

                                Loader {
                                    id: nativeSurfaceLoader

                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                    visible: taskCard.type === "native"
                                    active: taskCard.taskSwitcherVisible && taskCard.haveWayland && typeof taskCard.waylandSurface !== 'undefined' && taskCard.waylandSurface !== null
                                    source: taskCard.haveWayland ? "qrc:/qt/qml/MarathonOS/Shell/qml/components/WaylandShellSurfaceItem.qml" : ""
                                    onItemChanged: {
                                        if (item) {
                                            item.anchors.fill = nativeSurfaceLoader;
                                            item.autoResize = false;
                                            item.hasSentInitialSize = true;
                                            item.isMinimized = true;
                                        }
                                    }

                                    Binding {
                                        target: nativeSurfaceLoader.item
                                        property: "surfaceObj"
                                        value: taskCard.waylandSurface
                                        when: nativeSurfaceLoader.item !== null
                                    }

                                    Binding {
                                        target: nativeSurfaceLoader.item
                                        property: "touchEventsEnabled"
                                        value: false
                                        when: nativeSurfaceLoader.item !== null
                                    }

                                    Binding {
                                        target: nativeSurfaceLoader.item
                                        property: "inputEventsEnabled"
                                        value: false
                                        when: nativeSurfaceLoader.item !== null
                                    }
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
                    var p = closeButtonRect.mapToItem(handleTapArea, 0, 0);
                    if (mouse.x >= p.x && mouse.x <= p.x + closeButtonRect.width && mouse.y >= p.y && mouse.y <= p.y + closeButtonRect.height) {
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
                            if (typeof AppLifecycleManager !== 'undefined') {
                                if (appType !== "native")
                                    AppLifecycleManager.restoreApp(appId);
                                else
                                    AppLifecycleManager.bringToForeground(appId);
                            }
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
                    width: Constants.iconSizeMedium
                    height: Constants.iconSizeMedium

                    Rectangle {
                        id: closeButtonRect

                        anchors.centerIn: parent
                        width: Math.round(32 * Constants.scaleFactor)
                        height: Math.round(32 * Constants.scaleFactor)
                        radius: MRadius.sm
                        color: MColors.surface

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: closeButtonArea

                            anchors.fill: parent
                            anchors.margins: -12
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

    Behavior on scale {
        enabled: Constants.enableAnimations

        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }
}
