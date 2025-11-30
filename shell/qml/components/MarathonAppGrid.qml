import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: appGrid

    signal pageChanged(int currentPage, int totalPages)
    signal appLaunched(var app)
    signal longPress

    // Filtered app model
    property var appModel: filteredAppModel

    FilteredAppModel {
        id: filteredAppModel
        // No need for onCountChanged - pageCount property binding handles updates automatically
    }

    // Responsive grid layout based on screen width
    // Phone (< 700px): 4 columns × 5 rows
    // Small tablet (700-900px): 5 columns × 4 rows
    // Large tablet/desktop (> 900px): 6 columns × 4 rows
    property int columns: SettingsManagerCpp.appGridColumns > 0 ? SettingsManagerCpp.appGridColumns : (Constants.screenWidth < 700 ? 4 : (Constants.screenWidth < 900 ? 5 : 6))
    property int rows: Constants.screenWidth < 700 ? 5 : 4
    property int currentPage: 0
    // Property binding automatically updates when filteredAppModel.count, columns, or rows change
    property int pageCount: Math.ceil(filteredAppModel.count / (columns * rows))
    property real searchPullProgress: 0.0  // 0.0 to 1.0, tracks pull-down gesture
    property bool searchGestureActive: false  // Track if gesture is in progress

    // Smooth animation when resetting progress (only when gesture ends)
    Behavior on searchPullProgress {
        enabled: !searchGestureActive && searchPullProgress > 0.01 && !UIStore.searchOpen
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
            onRunningChanged: {
                // Force to 0 when animation completes
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
            Logger.info("AppGrid", "Auto-dismissing partial search overlay");
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

    Component.onCompleted: Logger.info("AppGrid", "Initialized with " + filteredAppModel.count + " apps")

    // No longer needed - FilteredAppModel handles this internally

    ListView {
        id: pageView
        anchors.fill: parent
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.DragAndOvershootBounds
        clip: true
        interactive: !UIStore.searchOpen && !appGrid.searchGestureActive  // Disable when search active
        flickableDirection: Flickable.HorizontalFlick
        highlightMoveDuration: 0  // Instant transitions - no animation delay
        preferredHighlightBegin: 0
        preferredHighlightEnd: width

        // Performance optimizations
        cacheBuffer: pageView.width * 2
        reuseItems: true
        displayMarginBeginning: 40
        displayMarginEnd: 40

        model: pageCount

        delegate: Item {
            width: pageView.width
            height: pageView.height

            Grid {
                id: iconGrid
                anchors.fill: parent
                anchors.margins: 12
                columns: appGrid.columns
                rows: appGrid.rows
                spacing: Constants.spacingMedium

                // Calculate visible range once per page
                readonly property int pageStartIdx: pageView.currentIndex * (appGrid.columns * appGrid.rows)
                readonly property int pageEndIdx: pageStartIdx + (appGrid.columns * appGrid.rows)

                Repeater {
                    model: filteredAppModel.count

                    Item {
                        width: (iconGrid.width - (appGrid.columns - 1) * iconGrid.spacing) / appGrid.columns
                        height: (iconGrid.height - (appGrid.rows - 1) * iconGrid.spacing) / appGrid.rows

                        // Optimized visibility: calculate once per page change
                        visible: index >= iconGrid.pageStartIdx && index < iconGrid.pageEndIdx

                        // Get app data from filtered model
                        readonly property var appData: filteredAppModel.getAppAtIndex(index)

                        // Optimized transform: NumberAnimation instead of SpringAnimation for press effects
                        transform: [
                            Scale {
                                origin.x: width / 2
                                origin.y: height / 2
                                xScale: iconMouseArea.pressed ? 0.95 : 1.0
                                yScale: iconMouseArea.pressed ? 0.95 : 1.0

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

                                // Press glow behind everything
                                Rectangle {
                                    id: pressGlow
                                    anchors.centerIn: parent
                                    width: parent.width * 1.2
                                    height: parent.height * 1.2
                                    radius: width / 2
                                    color: MColors.accentBright
                                    opacity: iconMouseArea.pressed ? 0.2 : 0.0
                                    visible: iconMouseArea.pressed
                                    z: 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 100
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                // Performant drop shadow (single dark layer, no blur)
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

                                // Actual icon on top
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

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: -4
                                    anchors.rightMargin: -4
                                    width: 20
                                    height: Constants.navBarHeight
                                    radius: 10
                                    color: MColors.error
                                    border.width: 2
                                    border.color: MColors.background
                                    antialiasing: Constants.enableAntialiasing
                                    visible: {
                                        if (!appData || !SettingsManagerCpp.showNotificationBadges)
                                            return false;
                                        var count = NotificationService.getNotificationCountForApp(appData.id);
                                        return count > 0;
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

                            property real pressX: 0
                            property real pressY: 0
                            property real pressTime: 0
                            property bool isSearchGesture: false
                            property real dragDistance: 0
                            readonly property real pullThreshold: 100  // Match page gesture
                            readonly property real commitThreshold: 0.35  // 35% commit

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
                                var deltaY = mouse.y - pressY;  // Positive = down
                                dragDistance = deltaY;

                                // Decide gesture direction - STRICT 3.0x ratio like page gesture
                                if (!isSearchGesture && deltaY > 10) {
                                    // STRICT: Vertical must be at least 3x horizontal (max ~18° angle)
                                    if (Math.abs(deltaY) > Math.abs(deltaX) * 3.0 && deltaY > 0) {
                                        isSearchGesture = true;
                                        // interactive is automatically disabled via binding when searchGestureActive becomes true
                                        Logger.info("AppGrid", "Icon search gesture started (deltaY: " + deltaY + ", angle ratio: " + (Math.abs(deltaY) / (deltaX || 1)).toFixed(1) + ")");
                                    }
                                }

                                // Update pull progress if it's a search gesture
                                if (isSearchGesture && deltaY > 0) {
                                    appGrid.searchGestureActive = true;
                                    appGrid.searchPullProgress = Math.min(1.0, deltaY / pullThreshold);
                                }
                            }

                            onReleased: mouse => {
                                appGrid.searchGestureActive = false;
                                // interactive is automatically re-enabled via binding when searchGestureActive becomes false

                                var deltaTime = Date.now() - pressTime;
                                var velocity = dragDistance / deltaTime;

                                // Open search if: past 35% OR velocity > 0.25px/ms
                                if (isSearchGesture && (appGrid.searchPullProgress > commitThreshold || velocity > 0.25)) {
                                    Logger.info("AppGrid", "Icon search opened (progress: " + (appGrid.searchPullProgress * 100).toFixed(0) + "%, velocity: " + velocity.toFixed(2) + "px/ms)");
                                    UIStore.openSearch();
                                    appGrid.searchPullProgress = 0.0;
                                    isSearchGesture = false;
                                    dragDistance = 0;
                                    return;
                                }

                                // Normal tap - launch app (only if not a search gesture)
                                if (!isSearchGesture && Math.abs(dragDistance) < 15 && deltaTime < 500) {
                                    if (!appData) {
                                        console.log("[AppGrid] CLICK REJECTED - No app data at index:", index);
                                        return;
                                    }
                                    console.log("[AppGrid] CLICK DETECTED - Launching app:", appData.name, "type:", appData.type, "exec:", appData.exec);
                                    Logger.info("AppGrid", "App launched: " + appData.name);
                                    appLaunched({
                                        id: appData.id,
                                        name: appData.name,
                                        icon: appData.icon,
                                        type: appData.type,
                                        exec: appData.exec
                                    });
                                    HapticService.medium();
                                } else {
                                    console.log("[AppGrid] Click rejected - isSearchGesture:", isSearchGesture, "dragDistance:", dragDistance, "deltaTime:", deltaTime);
                                }

                                isSearchGesture = false;
                                dragDistance = 0;
                            }

                            onPressAndHold: {
                                if (!appData)
                                    return;
                                Logger.info("AppGrid", "App long-pressed: " + appData.name);
                                var globalPos = mapToItem(appGrid.parent, mouseX, mouseY);
                                HapticService.heavy();

                                if (appGrid.parent && appGrid.parent.parent && appGrid.parent.parent.parent) {
                                    var shell = appGrid.parent.parent.parent;
                                    if (shell.appContextMenu) {
                                        shell.appContextMenu.show({
                                            id: appData.id,
                                            name: appData.name,
                                            icon: appData.icon,
                                            type: appData.type
                                        }, globalPos);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // GESTURE MASK OVERLAY - Only detects downward swipes, ignores everything else
            MouseArea {
                id: gestureMask
                anchors.fill: parent
                z: 100  // Above Grid but below icon MouseAreas (z:200)
                enabled: !UIStore.searchOpen

                property real pressX: 0
                property real pressY: 0
                property real pressTime: 0
                property bool isDownwardSwipe: false
                property real dragDistance: 0
                readonly property real pullThreshold: 100
                readonly property real commitThreshold: 0.35

                onPressed: mouse => {
                    pressX = mouse.x;
                    pressY = mouse.y;
                    pressTime = Date.now();
                    isDownwardSwipe = false;
                    dragDistance = 0;
                    // ALWAYS reject initially - let children handle
                    mouse.accepted = false;
                }

                onPositionChanged: mouse => {
                    var deltaX = Math.abs(mouse.x - pressX);
                    var deltaY = mouse.y - pressY;
                    dragDistance = deltaY;

                    // ONLY claim if it's a strict downward swipe
                    if (!isDownwardSwipe && deltaY > 10) {
                        if (Math.abs(deltaY) > Math.abs(deltaX) * 3.0 && deltaY > 0) {
                            // This is a downward swipe - claim it
                            isDownwardSwipe = true;
                            // interactive is automatically disabled via binding when searchGestureActive becomes true
                            mouse.accepted = true;
                            Logger.info("AppGrid", "Mask caught downward swipe in gap");
                        } else {
                            // Not downward - reject it (allows horizontal page swipes)
                            mouse.accepted = false;
                            return;
                        }
                    }

                    // Update progress only if we claimed this gesture
                    if (isDownwardSwipe && deltaY > 0) {
                        appGrid.searchGestureActive = true;
                        appGrid.searchPullProgress = Math.min(1.0, deltaY / pullThreshold);
                        mouse.accepted = true;
                    }
                }

                onReleased: mouse => {
                    if (isDownwardSwipe) {
                        appGrid.searchGestureActive = false;
                        // interactive is automatically re-enabled via binding when searchGestureActive becomes false

                        var deltaTime = Date.now() - pressTime;
                        var velocity = dragDistance / deltaTime;

                        if (appGrid.searchPullProgress > commitThreshold || velocity > 0.25) {
                            Logger.info("AppGrid", "Mask opened search from gap");
                            UIStore.openSearch();
                            appGrid.searchPullProgress = 0.0;
                        }
                        mouse.accepted = true;
                    }

                    isDownwardSwipe = false;
                    dragDistance = 0;
                }

                onCanceled: {
                    appGrid.searchGestureActive = false;
                    // interactive is automatically re-enabled via binding when searchGestureActive becomes false
                    isDownwardSwipe = false;
                    dragDistance = 0;
                }
            }
        }

        onCurrentIndexChanged: {
            appGrid.currentPage = currentIndex;
            pageChanged(currentPage, pageCount);
            Logger.debug("AppGrid", "Internal page changed to: " + currentIndex);
        }
    }

    function snapToPage(pageIndex) {
        pageView.positionViewAtIndex(pageIndex, ListView.Beginning);
    }

    function navigateToPage(pageIndex) {
        if (pageIndex >= 0 && pageIndex < pageCount) {
            pageView.currentIndex = pageIndex;
        }
    }
}
