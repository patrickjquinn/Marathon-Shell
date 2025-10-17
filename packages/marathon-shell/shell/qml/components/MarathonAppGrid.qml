import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: appGrid
    
    signal pageChanged(int currentPage, int totalPages)
    signal appLaunched(var app)
    signal longPress()
    
    property int columns: 4
    property int rows: 4
    property int currentPage: 0
    property int pageCount: Math.ceil(AppModel.count / (columns * rows))
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
                    appGrid.searchPullProgress = 0.0
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
            Logger.info("AppGrid", "Auto-dismissing partial search overlay")
            appGrid.searchPullProgress = 0.0
        }
    }
    
    // Reset to 0 if search closes while gesture active
    Connections {
        target: UIStore
        function onSearchOpenChanged() {
            if (!UIStore.searchOpen && !searchGestureActive) {
                appGrid.searchPullProgress = 0.0
            }
        }
    }
    
    Component.onCompleted: Logger.info("AppGrid", "Initialized with " + AppModel.count + " apps")
    
    Connections {
        target: AppModel
        function onCountChanged() {
            pageCount = Math.ceil(AppModel.count / (appGrid.columns * appGrid.rows))
            Logger.info("AppGrid", "App count changed: " + AppModel.count + ", pages: " + pageCount)
        }
    }
    
    // Full-page gesture detector - covers entire grid
    MouseArea {
        id: pageGestureArea
        anchors.fill: parent
        z: 1  // In front of ListView to catch gestures
        enabled: !UIStore.searchOpen
        propagateComposedEvents: true  // Let events through to children
        
        property real pressX: 0
        property real pressY: 0
        property real pressTime: 0
        property bool isSearchGesture: false
        property bool isHorizontalGesture: false
        property real dragDistance: 0
        readonly property real pullThreshold: 100  // Pixels to fully reveal search (reduced)
        readonly property real commitThreshold: 0.35  // 35% commit point (BB10-like)
        readonly property real gestureThreshold: 10  // Pixels before deciding direction
        
        onPressed: (mouse) => {
            pressX = mouse.x
            pressY = mouse.y
            pressTime = Date.now()
            isSearchGesture = false
            isHorizontalGesture = false
            dragDistance = 0
            appGrid.searchGestureActive = false
            mouse.accepted = false  // Don't claim yet - decide in onPositionChanged
        }
        
        onPositionChanged: (mouse) => {
            var deltaX = Math.abs(mouse.x - pressX)
            var deltaY = mouse.y - pressY  // Positive = down
            dragDistance = deltaY
            
            // Decide gesture direction after threshold
            if (!isSearchGesture && !isHorizontalGesture) {
                if (Math.abs(deltaX) > gestureThreshold || Math.abs(deltaY) > gestureThreshold) {
                    // Determine if this is vertical (search) or horizontal (page nav)
                    if (Math.abs(deltaY) > Math.abs(deltaX) * 1.5 && deltaY > 0) {
                        // Vertical down - search gesture
                        isSearchGesture = true
                        preventStealing = true  // NOW prevent ListView from stealing
                        Logger.info("AppGrid", "Page-wide search gesture started (deltaY: " + deltaY + ")")
                        mouse.accepted = true
                    } else {
                        // Horizontal or up - let ListView handle
                        isHorizontalGesture = true
                        mouse.accepted = false  // Let ListView take it
                        return  // Don't process further
                    }
                }
            }
            
            // Update pull progress only if it's our gesture
            if (isSearchGesture && deltaY > 0) {
                appGrid.searchGestureActive = true
                appGrid.searchPullProgress = Math.min(1.0, deltaY / pullThreshold)
            }
        }
        
        onReleased: (mouse) => {
            appGrid.searchGestureActive = false
            preventStealing = false  // Reset for next gesture
            
            var deltaTime = Date.now() - pressTime
            var velocity = dragDistance / deltaTime
            
            // Open search if: past 35% threshold OR velocity > 0.25px/ms
            if (isSearchGesture && (appGrid.searchPullProgress > commitThreshold || velocity > 0.25)) {
                Logger.info("AppGrid", "Page search opened (progress: " + (appGrid.searchPullProgress * 100).toFixed(0) + "%, velocity: " + velocity.toFixed(2) + "px/ms)")
                
                // Stop any ongoing page animation before opening search
                pageView.interactive = false
                pageView.interactive = true
                
                UIStore.openSearch()
                appGrid.searchPullProgress = 0.0  // Instant reset when opening
                mouse.accepted = true
            } else if (isSearchGesture) {
                // Search gesture but didn't meet threshold - accept to prevent page change
                mouse.accepted = true
            } else {
                // Not our gesture - let it propagate
                mouse.accepted = false
            }
            
            isSearchGesture = false
            isHorizontalGesture = false
            dragDistance = 0
        }
        
        onCanceled: {
            appGrid.searchGestureActive = false
            preventStealing = false
            isSearchGesture = false
            isHorizontalGesture = false
            dragDistance = 0
        }
    }
    
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
                anchors.fill: parent
                anchors.margins: 12
                columns: appGrid.columns
                rows: appGrid.rows
                spacing: Constants.spacingMedium
                
                Repeater {
                    model: AppModel
                    
                    Item {
                        width: (parent.width - (appGrid.columns - 1) * parent.spacing) / appGrid.columns
                        height: (parent.height - (appGrid.rows - 1) * parent.spacing) / appGrid.rows
                        
                        visible: {
                            var startIdx = pageView.currentIndex * (appGrid.columns * appGrid.rows)
                            var endIdx = startIdx + (appGrid.columns * appGrid.rows)
                            return index >= startIdx && index < endIdx
                        }
                        
                        transform: [
                            Scale {
                                origin.x: width / 2
                                origin.y: height / 2
                                xScale: iconMouseArea.pressed ? 0.95 : 1.0
                                yScale: iconMouseArea.pressed ? 0.95 : 1.0
                                
                                Behavior on xScale {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on yScale {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            },
                            Translate {
                                y: iconMouseArea.pressed ? -2 : 0
                                
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 150
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
                                    id: pressGlow
                                    anchors.centerIn: parent
                                    width: parent.width * 1.4
                                    height: parent.height * 1.4
                                    radius: width / 2
                                    color: "transparent"
                                    opacity: iconMouseArea.pressed ? 0.4 : 0.0
                                    
                                    border.width: iconMouseArea.pressed ? 20 : 0
                                    border.color: MColors.accentBright
                                    
                                    Behavior on opacity {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                    
                                    Behavior on border.width {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                    
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        blurEnabled: true
                                        blur: 1.0
                                        blurMax: 64
                                    }
                                }
                                
                                Image {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    source: model.icon
                                    width: parent.width
                                    height: parent.height
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                    cache: true
                                    sourceSize: Qt.size(width, height)
                                    z: 1
                                    
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowHorizontalOffset: 0
                                        shadowVerticalOffset: 4
                                        shadowBlur: 0.5
                                        shadowScale: 1.05
                                        shadowColor: Qt.rgba(0, 0, 0, 0.3)
                                    }
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
                                        var count = NotificationService.getNotificationCountForApp(model.id)
                                        return count > 0
                                    }
                                    
                                    Text {
                                        text: {
                                            var count = NotificationService.getNotificationCountForApp(model.id)
                                            return count > 9 ? "9+" : count.toString()
                                        }
                                        color: MColors.text
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.family: Typography.fontFamily
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                            
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: model.name
                                color: WallpaperStore.isDark ? MColors.text : "#000000"
                                font.pixelSize: Typography.sizeSmall
                                font.family: Typography.fontFamily
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
                            
                            onPressed: (mouse) => {
                                pressX = mouse.x
                                pressY = mouse.y
                                pressTime = Date.now()
                                isSearchGesture = false
                                dragDistance = 0
                                appGrid.searchGestureActive = false
                            }
                            
                            onPositionChanged: (mouse) => {
                                var deltaX = Math.abs(mouse.x - pressX)
                                var deltaY = mouse.y - pressY  // Positive = down
                                dragDistance = deltaY
                                
                                // Update pull progress
                                if (deltaY > 0) {
                                    appGrid.searchGestureActive = true
                                    appGrid.searchPullProgress = Math.min(1.0, deltaY / pullThreshold)
                                }
                                
                                // Quick flick down detection - more lenient
                                if (!isSearchGesture && deltaY > 15 && deltaY > deltaX * 1.2) {
                                    isSearchGesture = true
                                    Logger.info("AppGrid", "Icon search flick detected (deltaY: " + deltaY + ")")
                                }
                            }
                            
                            onReleased: (mouse) => {
                                appGrid.searchGestureActive = false
                                
                                var deltaTime = Date.now() - pressTime
                                var velocity = dragDistance / deltaTime
                                
                                // Open search if: past 35% OR velocity > 0.25px/ms
                                if (isSearchGesture && (appGrid.searchPullProgress > commitThreshold || velocity > 0.25)) {
                                    Logger.info("AppGrid", "Icon search opened (progress: " + (appGrid.searchPullProgress * 100).toFixed(0) + "%, velocity: " + velocity.toFixed(2) + "px/ms)")
                                    UIStore.openSearch()
                                    appGrid.searchPullProgress = 0.0  // Instant reset when opening
                                    isSearchGesture = false
                                    return
                                }
                                
                                // Normal tap - launch app
                                if (!isSearchGesture && Math.abs(dragDistance) < 15 && deltaTime < 500) {
                                    Logger.info("AppGrid", "App launched: " + model.name)
                                    appLaunched({
                                        id: model.id,
                                        name: model.name,
                                        icon: model.icon,
                                        type: model.type
                                    })
                                    HapticService.medium()
                                }
                                
                                // Let animation handle snap-back
                                isSearchGesture = false
                                dragDistance = 0
                            }
                            
                            onPressAndHold: {
                                Logger.info("AppGrid", "App long-pressed: " + model.name)
                                var globalPos = mapToItem(appGrid.parent, mouseX, mouseY)
                                HapticService.heavy()
                                
                                if (appGrid.parent && appGrid.parent.parent && appGrid.parent.parent.parent) {
                                    var shell = appGrid.parent.parent.parent
                                    if (shell.appContextMenu) {
                                        shell.appContextMenu.show({
                                            id: model.id,
                                            name: model.name,
                                            icon: model.icon,
                                            type: model.type
                                        }, globalPos)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        onCurrentIndexChanged: {
            currentPage = currentIndex
            pageChanged(currentPage, pageCount)
        }
    }
    
    function snapToPage(pageIndex) {
        pageView.positionViewAtIndex(pageIndex, ListView.Beginning)
    }
}

