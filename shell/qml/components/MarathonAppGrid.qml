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

        width: (iconGrid.width - (appGrid.columns - 1) * iconGrid.spacing) / appGrid.columns
        height: (iconGrid.height - (appGrid.rows - 1) * iconGrid.spacing) / appGrid.rows

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

            // 10 px between the squircle and the label per the
            // home-grid reference (screens-shell.jsx HomePage1).
            // 4 px (the previous value) packed labels visually
            // into the icon's drop shadow and made the row read
            // as a single block instead of icon + caption.
            spacing: Math.round(10 * (Constants.scaleFactor || 1.0))

            Item {
                id: iconBox

                anchors.horizontalCenter: parent.horizontalCenter
                width: Silica.Theme.iconSizeLauncher
                height: Silica.Theme.iconSizeLauncher

                // Press halo — soft teal glow at 18% beneath the
                // icon. Per DS Elevation · 'Active card' shadow,
                // the system uses a subtle bloom rather than a
                // hard fill on press. Squircle-radius matches
                // the app-icon shape rather than a full circle.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 1.15
                    height: parent.height * 1.15
                    radius: MRadius.squircle
                    color: MColors.tealHalo
                    opacity: iconMouseArea.pressed ? 1 : 0
                    visible: iconMouseArea.pressed
                    z: 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: MMotion.quick
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MAppIcon {
                    id: appIcon

                    source: iconCell.appData ? iconCell.appData.icon : ""
                    size: parent.width
                    anchors.centerIn: parent
                    z: 1
                }
            }

            // Silica's launcher label size, as on Sailfish's home.
            Text {
                width: parent.parent.width
                horizontalAlignment: Text.AlignHCenter
                text: iconCell.appData ? iconCell.appData.name : ""
                color: Silica.Theme.primaryColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeTiny
                // iOS Home Screen + Android launchers wrap to 2 lines
                // before truncating. At ≥1.25× canvas the cell width
                // can't hold "Calculator" / "App Store" / "Messages"
                // / "Calendar" in one line at the scaled footnote
                // size; wrap → fit instead of "Calcul…". Only at
                // word boundaries: one long word elides rather than
                // splitting as "Authenticat / or".
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

        required property int index
        readonly property IconCell cell: iconRepeater.count > index ? iconRepeater.itemAt(index) as IconCell : null
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

    // Drop shadow — DS app-icon frame spec
    // (app-icons.jsx AppIconFrame boxShadow):
    //   0 8px 16px -8px rgba(0,0,0,0.7)
    // Rendered as a translated, opacity-0.7 black squircle sitting 8 px
    // below the icon. Cheaper than a real blur and visually equivalent at
    // 64–80 px icon sizes against dark wallpapers.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.pageItemCount

            IconOverlay {
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    radius: MRadius.squircle
                    color: Qt.rgba(0, 0, 0, 0.7)
                    opacity: 0.35
                }
            }
        }
    }

    Grid {
        id: iconGrid

        anchors.fill: parent
        anchors.margins: 10
        anchors.bottomMargin: Constants.bottomBarHeight + 12
        columns: appGrid.columns
        rows: appGrid.rows
        // Tighter inter-cell spacing for higher density per user direction
        // — 8 px keeps icons legible while fitting 6 rows × 4 cols on
        // phone canvases without clipping.
        spacing: Math.round(8 * (Constants.scaleFactor || 1.0))

        Repeater {
            id: iconRepeater

            model: appGrid.pageItemCount

            IconCell {}
        }
    }

    // Outer 1 px black-60 ring — DS app-icon frame boxShadow:
    // `0 0 0 1px rgba(0,0,0,0.6)`. Gives each tile a hard edge against the
    // wallpaper without a heavy ring around the whole tile.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.pageItemCount

            IconOverlay {
                Rectangle {
                    anchors.fill: parent
                    radius: MRadius.squircle
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.6)
                }
            }
        }
    }

    // Inner 1 px white-15 TOP-only highlight — DS app-icon frame
    // `inset 0 1px 0 rgba(255,255,255,0.15)`. MTopHairline traces the top
    // arc of the squircle (PathArc → PathLine → PathArc) so the highlight
    // follows the corner radius instead of extending past it as a flat
    // horizontal bar.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.pageItemCount

            IconOverlay {
                MTopHairline {
                    radius: MRadius.squircle
                    color: Qt.rgba(1, 1, 1, 0.15)
                }
            }
        }
    }

    // Notification badge — tealBright per DS Badges spec
    // (ds-components.jsx). Marathon DS uses teal-on-black for counts; the
    // previous red was off-brand. The 2 px black ring sits the badge off
    // the icon edge cleanly.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.pageItemCount

            IconOverlay {
                id: badgeOverlay

                readonly property var appData: cell ? cell.appData : null

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -4
                    anchors.rightMargin: -4
                    width: 20
                    height: 20
                    radius: 10
                    color: MColors.marathonTealBright
                    border.width: 2
                    border.color: MColors.elev0
                    visible: {
                        if (!badgeOverlay.appData || !SettingsManagerCpp.showNotificationBadges)
                            return false;

                        return NotificationService.getNotificationCountForApp(badgeOverlay.appData.id) > 0;
                    }

                    Text {
                        text: {
                            if (!badgeOverlay.appData)
                                return "";

                            var count = NotificationService.getNotificationCountForApp(badgeOverlay.appData.id);
                            return count > 9 ? "9+" : count.toString();
                        }
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
