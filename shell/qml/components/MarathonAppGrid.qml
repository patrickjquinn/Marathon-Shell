pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/LauncherGrid.js" as LauncherGrid

Item {
    id: appGrid

    property var appModel: null
    property int pageIndex: 0
    property int columns: LauncherGrid.columns(Constants.screenWidth, Silica.Theme.iconSizeLauncher, SettingsManagerCpp.appGridColumns)
    property int rows: LauncherGrid.rows(Constants.screenHeight, Silica.Theme.iconSizeLauncher)
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
    // Unread counts for this page's apps, as {index, count}. Only badged
    // icons get an overlay.
    readonly property var badges: {
        const notifications = NotificationService.notifications;
        if (!appModel || !SettingsManagerCpp.showNotificationBadges || notifications.length === 0)
            return [];
        const out = [];
        for (let i = 0; i < pageItemCount; ++i) {
            const app = appModel.getAppAtIndex(startIndex + i);
            const count = app ? NotificationService.getNotificationCountForApp(app.id) : 0;
            if (count > 0)
                out.push({
                    "index": i,
                    "count": count
                });
        }
        return out;
    }

    signal appLaunched(var app)
    signal longPress(var app, rect sceneRect)

    Timer {
        id: autoDismissTimer

        interval: 50
        running: !appGrid.searchGestureActive && appGrid.searchPullProgress > 0.01 && appGrid.searchPullProgress < 0.99 && !UIStore.searchOpen
        repeat: false
        onTriggered: {
            appGrid.searchPullProgress = 0;
        }
    }

    Connections {
        function onSearchOpenChanged() {
            if (!UIStore.searchOpen && !appGrid.searchGestureActive)
                appGrid.searchPullProgress = 0;
        }

        target: UIStore
    }

    component IconCell: Item {
        id: iconCell

        required property int index
        readonly property var appData: appGrid.appModel ? appGrid.appModel.getAppAtIndex(appGrid.startIndex + index) : null
        // Read by IconOverlay to place this icon's decorations.
        readonly property Item contentColumn: contentColumn
        readonly property Item iconBox: iconBox

        width: iconGrid.width / appGrid.columns
        height: (iconGrid.height - (appGrid.rows - 1) * iconGrid.rowSpacing) / appGrid.rows

        Accessible.role: Accessible.Button
        Accessible.name: appData ? appData.name : ""
        Accessible.ignored: !appData
        Accessible.onPressAction: if (appData)
            appGrid.appLaunched(appData)

        // Staggered entrance — every home grid icon fades up in a
        // light wave on first paint. Index-based delay means the
        // top-left icon arrives first, the rest cascade. The cost
        // is one ParallelAnimation per cell that runs ONCE then
        // never again; cells reused on page change keep their
        // already-played state.
        MEntrance {
            target: iconCell
            index: iconCell.index
            stagger: MMotion.staggerMicro
        }

        // Press feedback scales and lifts this column, not the cell:
        // a transform list on every cell (even at scale 1) gives
        // each icon a non-translate matrix, which stops Qt Quick
        // merging the antialiased shapes and labels across icons
        // (126 draw calls per frame on the home screen). The
        // scale property at 1.0 leaves the matrix translate-only.
        // The cell itself is left to MEntrance, which writes its
        // scale and y.
        Column {
            id: contentColumn

            anchors.centerIn: parent
            anchors.verticalCenterOffset: iconMouseArea.pressed ? -2 : 0
            scale: iconMouseArea.pressed ? 0.95 : 1

            Behavior on scale {
                enabled: Constants.enableAnimations

                NumberAnimation {
                    duration: MMotion.durationFor("microPress")
                    easing.type: MMotion.easingFor("microPress")
                }
            }

            Behavior on anchors.verticalCenterOffset {
                enabled: Constants.enableAnimations

                NumberAnimation {
                    duration: MMotion.durationFor("microPress")
                    easing.type: MMotion.easingFor("microPress")
                }
            }

            spacing: Math.round(10 * (Constants.scaleFactor || 1.0))

            Item {
                id: iconBox

                anchors.horizontalCenter: parent.horizontalCenter
                width: Silica.Theme.iconSizeLauncher
                height: Silica.Theme.iconSizeLauncher

                // Pressed: the icon itself dims, as on Sailfish's launcher.
                MAppIcon {
                    id: appIcon

                    source: iconCell.appData ? iconCell.appData.icon : ""
                    size: parent.width
                    anchors.centerIn: parent
                    opacity: iconMouseArea.pressed ? Silica.Theme.opacityHigh : 1
                }
            }

            // Silica's launcher label size, as on Sailfish's home.
            Text {
                width: iconCell.width - Silica.Theme.paddingSmall
                horizontalAlignment: Text.AlignHCenter
                text: iconCell.appData ? iconCell.appData.name : ""
                color: Silica.Theme.primaryColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeTiny
                // Names longer than the column wrap to a second line at word
                // boundaries; one long word elides rather than splitting.
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
        }

        MouseArea {
            id: iconMouseArea

            property real pressX: 0
            property real pressY: 0
            property real pressTime: 0
            property bool isSearchGesture: false
            property bool held: false
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
                held = false;
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
                if (!isSearchGesture && !held && Math.abs(dragDistance) < 15) {
                    if (iconCell.appData) {
                        appGrid.appLaunched(iconCell.appData);
                        HapticManager.medium();
                    }
                }
                isSearchGesture = false;
            }
            onPressAndHold: {
                held = true;
                if (iconCell.appData) {
                    appGrid.longPress(iconCell.appData, iconCell.mapToItem(null, 0, 0, iconCell.width, iconCell.height));
                    HapticManager.medium();
                }
            }
        }
    }

    // Decorations live in per-kind layers so each layer batches; IconOverlay
    // tracks its cell's position, entrance and press transforms.
    component IconOverlay: Item {
        id: overlay

        property int cellIndex: -1
        readonly property IconCell cell: cellIndex >= 0 && iconRepeater.count > cellIndex ? iconRepeater.itemAt(cellIndex) as IconCell : null
        default property alias content: iconArea.data

        x: cell ? cell.x : 0
        y: cell ? cell.y : 0
        width: cell ? cell.width : 0
        height: cell ? cell.height : 0
        scale: cell ? cell.scale : 1
        opacity: cell ? cell.opacity : 0
        visible: cell !== null

        Item {
            x: overlay.cell ? overlay.cell.contentColumn.x : 0
            y: overlay.cell ? overlay.cell.contentColumn.y : 0
            width: overlay.cell ? overlay.cell.contentColumn.width : 0
            height: overlay.cell ? overlay.cell.contentColumn.height : 0
            scale: overlay.cell ? overlay.cell.contentColumn.scale : 1

            Item {
                id: iconArea

                x: overlay.cell ? overlay.cell.iconBox.x : 0
                width: Silica.Theme.iconSizeLauncher
                height: Silica.Theme.iconSizeLauncher
            }
        }
    }

    Grid {
        id: iconGrid

        anchors.fill: parent
        anchors.topMargin: 10
        // The page margin every app and the dock use, so the outer columns
        // line up with the rest of the UI instead of running to the edges.
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        anchors.bottomMargin: Constants.bottomBarHeight + 12
        columns: appGrid.columns
        rows: appGrid.rows
        // Labels take the whole column pitch; the icons are narrower anyway.
        columnSpacing: 0
        rowSpacing: Math.round(8 * (Constants.scaleFactor || 1.0))

        Repeater {
            id: iconRepeater

            model: appGrid.pageItemCount

            IconCell {}
        }
    }

    // Notification badge — tealBright per DS Badges spec
    // (ds-components.jsx). Marathon DS uses teal-on-black for counts; the
    // previous red was off-brand. The 2 px black ring sits the badge off
    // the icon edge cleanly.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.badges

            IconOverlay {
                id: badgeOverlay

                required property var modelData

                cellIndex: modelData.index

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -4
                    anchors.rightMargin: -4
                    height: badgeLabel.font.pixelSize + 8
                    width: Math.max(height, badgeLabel.implicitWidth + 10)
                    radius: height / 2
                    color: MColors.marathonTealBright
                    border.width: 2
                    border.color: MColors.elev0

                    Text {
                        id: badgeLabel

                        text: badgeOverlay.modelData.count > 9 ? "9+" : badgeOverlay.modelData.count.toString()
                        color: MColors.textOnAccent
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: MTypography.weightDemiBold
                        font.features: ({
                                "tnum": 1
                            })
                        anchors.centerIn: parent
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
        enabled: !appGrid.searchGestureActive && appGrid.searchPullProgress > 0.01 && !UIStore.searchOpen

        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
            onRunningChanged: {
                if (!running && appGrid.searchPullProgress < 0.02)
                    appGrid.searchPullProgress = 0;
            }
        }
    }
}
