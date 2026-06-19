import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import MarathonOS.Shell 1.0
import QtQuick

Item {
    id: appGrid

    property var appModel: null
    property int pageIndex: 0
    // Scale-aware grid density. iOS does exactly this — bump Display Size
    // in Settings and the Home Screen drops from 4×6 to 3×6 once icons
    // grow past comfortable density. At Marathon's userScaleFactor ≥ 1.25,
    // each cell footprint (icon + halo + label) exceeds 1/4 screen and the
    // Grid wraps to a single column. 3 × 4 = 12/page restores the layout
    // and keeps thumb-reach proportional to icon size.
    // Hit SettingsManagerCpp directly (skip Constants) so the binding is
    // unambiguously tied to the live user-scale signal — and stash it on a
    // readonly so column/row both bind to the same notifier and re-evaluate
    // together when the user changes Display Size.
    readonly property real _userScale: SettingsManagerCpp.userScaleFactor
    // Bucket the base column/row count by canvas width — phone, small
    // tablet (HyperPixel CM5 720×720), and wider. Higher userScale grows
    // every icon's footprint proportionally, so fewer cells fit. Use
    // floor(base / scale) but clamp the divisor at 1.0 so the grid never
    // ADDS columns when scale drops below 1.0 — getting 6-wide on a phone
    // at scale 0.7 would look absurd. Floor at 3 so the bottom row never
    // collapses to a single icon when scale → 2.0 on a small canvas.
    readonly property int _baseColumns: Constants.screenWidth < 700 ? 4 : Constants.screenWidth < 900 ? 5 : 6
    readonly property int _baseRows: Constants.screenWidth < 700 ? 4 : 5
    readonly property real _scaleDivisor: Math.max(1.0, _userScale)
    property int columns: SettingsManagerCpp.appGridColumns > 0 ? SettingsManagerCpp.appGridColumns : Math.max(3, Math.floor(_baseColumns / _scaleDivisor))
    property int rows: Math.max(4, Math.floor(_baseRows / _scaleDivisor))
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
        anchors.margins: 10
        anchors.bottomMargin: Constants.bottomBarHeight + 12
        columns: appGrid.columns
        rows: appGrid.rows
        // Tighter inter-cell spacing for higher density per user direction
        // — 8 px keeps icons legible while fitting 6 rows × 4 cols on
        // phone canvases without clipping.
        spacing: Math.round(8 * (Constants.scaleFactor || 1.0))

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
                    // 10 px between the squircle and the label per the
                    // home-grid reference (screens-shell.jsx HomePage1).
                    // 4 px (the previous value) packed labels visually
                    // into the icon's drop shadow and made the row read
                    // as a single block instead of icon + caption.
                    spacing: Math.round(10 * (Constants.scaleFactor || 1.0))

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Constants.appIconSize
                        height: Constants.appIconSize

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

                        // Drop shadow — DS app-icon frame spec
                        // (app-icons.jsx AppIconFrame boxShadow):
                        //   0 8px 16px -8px rgba(0,0,0,0.7)
                        // Rendered as a translated, opacity-0.7 black
                        // squircle sitting 8 px below the icon. Cheaper
                        // than a real blur and visually equivalent at
                        // 64–80 px icon sizes against dark wallpapers.
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 8
                            radius: MRadius.squircle
                            color: Qt.rgba(0, 0, 0, 0.7)
                            opacity: 0.35
                            z: 0
                        }

                        MAppIcon {
                            id: appIcon

                            source: appData ? appData.icon : ""
                            size: parent.width
                            anchors.centerIn: parent
                            z: 1
                        }

                        // Outer 1 px black-60 ring — DS app-icon frame
                        // boxShadow: `0 0 0 1px rgba(0,0,0,0.6)`. Gives
                        // each tile a hard edge against the wallpaper
                        // without a heavy ring around the whole tile.
                        Rectangle {
                            anchors.fill: parent
                            radius: MRadius.squircle
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.6)
                            z: 2
                        }

                        // Inner 1 px white-15 TOP-only highlight — DS
                        // app-icon frame `inset 0 1px 0 rgba(255,255,255,0.15)`.
                        // MTopHairline traces the top arc of the
                        // squircle (PathArc → PathLine → PathArc) so
                        // the highlight follows the corner radius
                        // instead of extending past it as a flat
                        // horizontal bar.
                        MTopHairline {
                            radius: MRadius.squircle
                            color: Qt.rgba(1, 1, 1, 0.15)
                            z: 3
                        }

                        // Notification badge — tealBright per DS Badges
                        // spec (ds-components.jsx). Marathon DS uses
                        // teal-on-black for counts; the previous red was
                        // off-brand. The 2 px black ring sits the badge
                        // off the icon edge cleanly.
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

                    // App label — Footnote 13 / 500 per user direction
                    // ("make icons and text bigger"). textPrimary on dark
                    // wallpapers; Text.Outline dropped since the DS dark-
                    // first surface doesn't need it.
                    Text {
                        width: parent.parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: appData ? appData.name : ""
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        font.weight: MTypography.weightMedium
                        // iOS Home Screen + Android launchers wrap to 2 lines
                        // before truncating. At ≥1.25× canvas the cell width
                        // can't hold "Calculator" / "App Store" / "Messages"
                        // / "Calendar" in one line at the scaled footnote
                        // size; wrap → fit instead of "Calcul…".
                        wrapMode: Text.Wrap
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
