import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: appGrid

    // Signals
    signal appLaunched(var app)
    signal longPress

    // Properties passed from parent (MarathonPageView)
    property var appModel: null
    property int pageIndex: 0
    
    // Grid configuration
    property int columns: SettingsManagerCpp.appGridColumns > 0 ? SettingsManagerCpp.appGridColumns : (Constants.screenWidth < 700 ? 4 : (Constants.screenWidth < 900 ? 5 : 6))
    property int rows: Constants.screenWidth < 700 ? 5 : 4
    property int itemsPerPage: columns * rows
    
    // Search gesture properties
    property real searchPullProgress: 0.0
    property bool searchGestureActive: false

    // Calculate start index for this page
    readonly property int startIndex: pageIndex * itemsPerPage
    
    // Calculate how many items to show on this page
    readonly property int pageItemCount: {
        if (!appModel) return 0;
        var remaining = appModel.count - startIndex;
        return Math.max(0, Math.min(remaining, itemsPerPage));
    }

    // Smooth animation when resetting progress
    Behavior on searchPullProgress {
        enabled: !searchGestureActive && searchPullProgress > 0.01 && !UIStore.searchOpen
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
            onRunningChanged: {
                if (!running && searchPullProgress < 0.02) {
                    appGrid.searchPullProgress = 0.0;
                }
            }
        }
    }

    // Auto-dismiss if gesture ends and search not fully open
    Timer {
        id: autoDismissTimer
        interval: 50
        running: !searchGestureActive && searchPullProgress > 0.01 && searchPullProgress < 0.99 && !UIStore.searchOpen
        repeat: false
        onTriggered: {
            appGrid.searchPullProgress = 0.0;
        }
    }

    // Reset to 0 if search closes while gesture active
    Connections {
        target: UIStore
        function onSearchOpenChanged() {
            if (!UIStore.searchOpen && !searchGestureActive) {
                appGrid.searchPullProgress = 0.0;
            }
        }
    }

    // Main Grid Layout
    Grid {
        id: iconGrid
        anchors.fill: parent
        anchors.margins: 12
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        columns: appGrid.columns
        rows: appGrid.rows
        spacing: Constants.spacingMedium

        Repeater {
            model: appGrid.pageItemCount

            Item {
                width: (iconGrid.width - (appGrid.columns - 1) * iconGrid.spacing) / appGrid.columns
                height: (iconGrid.height - (appGrid.rows - 1) * iconGrid.spacing) / appGrid.rows

                // Get app data from shared model using offset
                readonly property var appData: appGrid.appModel ? appGrid.appModel.getAppAtIndex(appGrid.startIndex + index) : null

                // Icon Transform Animation
                transform: [
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: iconMouseArea.pressed ? 0.95 : 1.0
                        yScale: iconMouseArea.pressed ? 0.95 : 1.0

                        Behavior on xScale {
                            enabled: Constants.enableAnimations
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        Behavior on yScale {
                            enabled: Constants.enableAnimations
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    },
                    Translate {
                        y: iconMouseArea.pressed ? -2 : 0
                        Behavior on y {
                            enabled: Constants.enableAnimations
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }
                ]

                Column {
                    anchors.centerIn: parent
                    spacing: Constants.spacingSmall

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Constants.appIconSize
                        height: Constants.appIconSize

                        // Press glow
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 1.2
                            height: parent.height * 1.2
                            radius: width / 2
                            color: MColors.accentBright
                            opacity: iconMouseArea.pressed ? 0.2 : 0.0
                            visible: iconMouseArea.pressed
                            z: 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }

                        // Shadow
                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 4
                            source: appData ? appData.icon : ""
                            width: parent.width
                            height: parent.height
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(width, height)
                            opacity: 0.4
                            z: 1
                        }

                        // Icon
                        Image {
                            id: appIcon
                            anchors.centerIn: parent
                            source: appData ? appData.icon : ""
                            width: parent.width
                            height: parent.height
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(width, height)
                            z: 2
                        }

                        // Notification Badge
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -4
                            anchors.rightMargin: -4
                            width: 20
                            height: 20
                            radius: 10
                            color: MColors.error
                            border.width: 2
                            border.color: MColors.background
                            visible: {
                                if (!appData || !SettingsManagerCpp.showNotificationBadges) return false;
                                return NotificationService.getNotificationCountForApp(appData.id) > 0;
                            }

                            Text {
                                text: {
                                    if (!appData) return "";
                                    var count = NotificationService.getNotificationCountForApp(appData.id);
                                    return count > 9 ? "9+" : count.toString();
                                }
                                color: MColors.text
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.family: MTypography.fontFamily
                                anchors.centerIn: parent
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: appData ? appData.name : ""
                        color: WallpaperStore.isDark ? MColors.text : "#000000"
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: iconMouseArea
                    anchors.fill: parent
                    z: 200
                    preventStealing: false

                    property real pressX: 0
                    property real pressY: 0
                    property real pressTime: 0
                    property bool isSearchGesture: false
                    property real dragDistance: 0
                    readonly property real pullThreshold: 100
                    readonly property real commitThreshold: 0.35

                    onPressed: mouse => {
                        pressX = mouse.x;
                        pressY = mouse.y;
                        pressTime = Date.now();
                        isSearchGesture = false;
                        dragDistance = 0;
                        appGrid.searchGestureActive = false;
                    }

                    onPositionChanged: mouse => {
                        var deltaX = Math.abs(mouse.x - pressX);
                        var deltaY = mouse.y - pressY;
                        dragDistance = deltaY;

                        if (!isSearchGesture && deltaY > 10) {
                            if (Math.abs(deltaY) > Math.abs(deltaX) * 3.0 && deltaY > 0) {
                                isSearchGesture = true;
                            }
                        }

                        if (isSearchGesture && deltaY > 0) {
                            appGrid.searchGestureActive = true;
                            appGrid.searchPullProgress = Math.min(1.0, deltaY / pullThreshold);
                        }
                    }

                    onReleased: mouse => {
                        appGrid.searchGestureActive = false;
                        var deltaTime = Date.now() - pressTime;
                        var velocity = dragDistance / deltaTime;

                        if (isSearchGesture && (appGrid.searchPullProgress > commitThreshold || velocity > 0.25)) {
                            UIStore.openSearch();
                            appGrid.searchPullProgress = 0.0;
                            isSearchGesture = false;
                            return;
                        }

                        if (!isSearchGesture && Math.abs(dragDistance) < 15 && deltaTime < 500) {
                            if (appData) {
                                appGrid.appLaunched(appData);
                                HapticService.medium();
                            }
                        }
                        isSearchGesture = false;
                    }

                    onPressAndHold: {
                        if (appData) {
                            var globalPos = mapToItem(appGrid.parent, mouseX, mouseY);
                            HapticService.heavy();
                            // Context menu logic would go here
                            appGrid.longPress();
                        }
                    }
                }
            }
        }
    }

    // GESTURE MASK (for gaps between icons)
    MouseArea {
        id: gestureMask
        anchors.fill: parent
        z: 100
        enabled: !UIStore.searchOpen

        property real pressX: 0
        property real pressY: 0
        property bool isDownwardSwipe: false
        property real dragDistance: 0
        readonly property real pullThreshold: 100

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            isDownwardSwipe = false;
            mouse.accepted = false;
        }

        onPositionChanged: mouse => {
            var deltaX = Math.abs(mouse.x - pressX);
            var deltaY = mouse.y - pressY;
            dragDistance = deltaY;

            if (!isDownwardSwipe && deltaY > 10) {
                if (Math.abs(deltaY) > Math.abs(deltaX) * 3.0 && deltaY > 0) {
                    isDownwardSwipe = true;
                    mouse.accepted = true;
                } else {
                    mouse.accepted = false;
                    return;
                }
            }

            if (isDownwardSwipe && deltaY > 0) {
                appGrid.searchGestureActive = true;
                appGrid.searchPullProgress = Math.min(1.0, deltaY / pullThreshold);
                mouse.accepted = true;
            }
        }

        onReleased: mouse => {
            if (isDownwardSwipe) {
                appGrid.searchGestureActive = false;
                if (appGrid.searchPullProgress > 0.35) {
                    UIStore.openSearch();
                    appGrid.searchPullProgress = 0.0;
                }
                mouse.accepted = true;
            }
            isDownwardSwipe = false;
        }
    }
}
