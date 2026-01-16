import MarathonUI.Core
import MarathonUI.Theme
import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects

Item {
    id: appGrid

    property var appModel: null
    property int pageIndex: 0
    property int columns: SettingsManagerCpp.appGridColumns > 0 ? SettingsManagerCpp.appGridColumns : (Constants.screenWidth < 700 ? 4 : (Constants.screenWidth < 900 ? 5 : 6))
    property int rows: Constants.screenWidth < 700 ? 5 : 4
    property int itemsPerPage: columns * rows
    property real searchPullProgress: 0
    property bool searchGestureActive: false
    readonly property int startIndex: pageIndex * itemsPerPage
    readonly property int pageItemCount: {
        if (!appModel)
            return 0;

        var remaining = appModel.count - startIndex;
        return Math.max(0, Math.min(remaining, itemsPerPage));
    }

    signal appLaunched(var app)
    signal longPress

    Timer {
        id: autoDismissTimer

        interval: 50
        running: !searchGestureActive && searchPullProgress > 0.01 && searchPullProgress < 0.99 && !UIStore.searchOpen
        repeat: false
        onTriggered: {
            appGrid.searchPullProgress = 0;
        }
    }

    Connections {
        function onSearchOpenChanged() {
            if (!UIStore.searchOpen && !searchGestureActive)
                appGrid.searchPullProgress = 0;
        }

        target: UIStore
    }

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
                readonly property var appData: appGrid.appModel ? appGrid.appModel.getAppAtIndex(appGrid.startIndex + index) : null

                width: (iconGrid.width - (appGrid.columns - 1) * iconGrid.spacing) / appGrid.columns
                height: (iconGrid.height - (appGrid.rows - 1) * iconGrid.spacing) / appGrid.rows
                transform: [
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: iconMouseArea.pressed ? 0.95 : 1
                        yScale: iconMouseArea.pressed ? 0.95 : 1

                        Behavior on xScale {
                            enabled: Constants.enableAnimations

                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on yScale {
                            enabled: Constants.enableAnimations

                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    },
                    Translate {
                        y: iconMouseArea.pressed ? -2 : 0

                        Behavior on y {
                            enabled: Constants.enableAnimations

                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
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

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 1.2
                            height: parent.height * 1.2
                            radius: width / 2
                            color: MColors.accentBright
                            opacity: iconMouseArea.pressed ? 0.2 : 0
                            visible: iconMouseArea.pressed
                            z: 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 100
                                }
                            }
                        }

                        MAppIcon {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 2
                            source: appData ? appData.icon : ""
                            size: parent.width
                            opacity: 0.3
                            color: "black"
                            z: 1
                        }

                        MAppIcon {
                            id: appIcon

                            source: appData ? appData.icon : ""
                            size: parent.width
                            anchors.centerIn: parent
                            z: 2
                        }

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
                                if (!appData || !SettingsManagerCpp.showNotificationBadges)
                                    return false;

                                return NotificationService.getNotificationCountForApp(appData.id) > 0;
                            }

                            Text {
                                text: {
                                    if (!appData)
                                        return "";

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
                        width: parent.parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: appData ? appData.name : ""
                        color: WallpaperStore.isDark ? MColors.text : "#000000"
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.6)
                    }
                }

                MouseArea {
                    id: iconMouseArea

                    property real pressX: 0
                    property real pressY: 0
                    property real pressTime: 0
                    property bool isSearchGesture: false
                    property real dragDistance: 0
                    readonly property real pullThreshold: 100
                    readonly property real commitThreshold: 0.35

                    anchors.fill: parent
                    z: 200
                    preventStealing: false
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
                            if (Math.abs(deltaY) > Math.abs(deltaX) * 3 && deltaY > 0)
                                isSearchGesture = true;
                        }
                        if (isSearchGesture && deltaY > 0) {
                            appGrid.searchGestureActive = true;
                            appGrid.searchPullProgress = Math.min(1, deltaY / pullThreshold);
                        }
                    }
                    onReleased: mouse => {
                        appGrid.searchGestureActive = false;
                        var deltaTime = Date.now() - pressTime;
                        var velocity = dragDistance / deltaTime;
                        if (isSearchGesture && (appGrid.searchPullProgress > commitThreshold || velocity > 0.25)) {
                            UIStore.openSearch();
                            appGrid.searchPullProgress = 0;
                            isSearchGesture = false;
                            return;
                        }
                        if (!isSearchGesture && Math.abs(dragDistance) < 15 && deltaTime < 500) {
                            if (appData) {
                                appGrid.appLaunched(appData);
                                HapticManager.medium();
                            }
                        }
                        isSearchGesture = false;
                    }
                    onPressAndHold: {
                        if (appData) {
                            var globalPos = mapToItem(appGrid.parent, mouseX, mouseY);
                            HapticManager.heavy();
                            appGrid.longPress();
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: gestureMask

        property real pressX: 0
        property real pressY: 0
        property bool isDownwardSwipe: false
        property real dragDistance: 0
        readonly property real pullThreshold: 100

        anchors.fill: parent
        z: 100
        enabled: !UIStore.searchOpen
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
                if (Math.abs(deltaY) > Math.abs(deltaX) * 3 && deltaY > 0) {
                    isDownwardSwipe = true;
                    mouse.accepted = true;
                } else {
                    mouse.accepted = false;
                    return;
                }
            }
            if (isDownwardSwipe && deltaY > 0) {
                appGrid.searchGestureActive = true;
                appGrid.searchPullProgress = Math.min(1, deltaY / pullThreshold);
                mouse.accepted = true;
            }
        }
        onReleased: mouse => {
            if (isDownwardSwipe) {
                appGrid.searchGestureActive = false;
                if (appGrid.searchPullProgress > 0.35) {
                    UIStore.openSearch();
                    appGrid.searchPullProgress = 0;
                }
                mouse.accepted = true;
            }
            isDownwardSwipe = false;
        }
    }

    Behavior on searchPullProgress {
        enabled: !searchGestureActive && searchPullProgress > 0.01 && !UIStore.searchOpen

        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
            onRunningChanged: {
                if (!running && searchPullProgress < 0.02)
                    appGrid.searchPullProgress = 0;
            }
        }
    }
}
