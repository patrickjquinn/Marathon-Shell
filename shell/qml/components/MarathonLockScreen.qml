import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonOS.Shell 1.0 as Shell
import MarathonUI.Core
import "."
import "./ui"
import MarathonUI.Theme

Item {
    id: lockScreen
    anchors.fill: parent
    
    signal unlockRequested()
    signal cameraLaunched()
    signal phoneLaunched()
    signal notificationTapped(int notifId, string appId, string title)
    
    property real swipeProgress: 0.0
    property string expandedCategory: ""  // Track which notification category is expanded
    property int idleTimeoutMs: 30000  // 30 seconds idle timeout before blanking screen
    
    // Keep lock screen visible during entire swipe (only hide when opacity reaches 0)
    // This prevents home screen flash-through
    visible: opacity > 0.01
    
    // Idle timer to blank screen after inactivity
    Timer {
        id: idleTimer
        interval: idleTimeoutMs
        running: lockScreen.visible && DisplayManager.screenOn
        repeat: false
        onTriggered: {
            Logger.info("LockScreen", "Idle timeout - blanking screen")
            DisplayManager.turnScreenOff()
        }
    }
    
    // Reset idle timer on any user interaction
    function resetIdleTimer() {
        if (lockScreen.visible && DisplayManager.screenOn) {
            idleTimer.restart()
        }
    }
    
    // Auto-expand notifications when they arrive while on lock screen
    Connections {
        target: NotificationService
        function onNotificationReceived(notification) {
            if (lockScreen.visible) {
                Logger.info("LockScreen", "New notification while on lock screen: " + notification.title)
                
                // Wake screen if off
                if (!DisplayManager.screenOn) {
                    DisplayManager.turnScreenOn()
                }
                
                // Auto-expand the notification's category
                var appId = notification.appId || "other"
                expandedCategory = appId
                
                // Reset idle timer
                resetIdleTimer()
                
                Logger.info("LockScreen", "Auto-expanded category: " + appId)
            }
        }
    }
    
    // Restart idle timer when screen turns on
    Connections {
        target: DisplayManager
        function onScreenStateChanged(isOn) {
            if (isOn) {
                // Show lock screen when screen turns on (preserves grace period if unlocked)
                SessionStore.showLock()
                if (lockScreen.visible) {
                    Logger.info("LockScreen", "Screen turned on - starting idle timer")
                    resetIdleTimer()
                }
            }
            // Note: Don't lock the session when screen turns off - preserve grace period!
            // When screen turns on, showLock() displays lock screen but keeps isLocked state
        }
    }
    
    // Categories Model - Moved to top level for reliable access
    ListModel {
        id: categoriesModel
    }
    
    // Update categories function
    function updateCategories() {
        var cats = {}
        
        // Iterate through NotificationModel using Repeater pattern
        for (var i = 0; i < NotificationModel.rowCount(); i++) {
            var idx = NotificationModel.index(i, 0)
            var isRead = NotificationModel.data(idx, Shell.NotificationRoles.IsReadRole) || false
            
            // Skip read notifications
            if (isRead) continue
            
            var appId = NotificationModel.data(idx, Shell.NotificationRoles.AppIdRole) || "other"
            var icon = NotificationModel.data(idx, Shell.NotificationRoles.IconRole) || "bell"
            
            if (!cats[appId]) {
                cats[appId] = {
                    appId: appId,
                    icon: icon,
                    count: 0
                }
            }
            cats[appId].count++
        }
        
        // Rebuild model
        categoriesModel.clear()
        for (var cat in cats) {
            categoriesModel.append(cats[cat])
        }
        
        Logger.info("LockScreen", "Updated categories. Count: " + categoriesModel.count)
    }
    
    // Update categories when notifications change
    Connections {
        target: NotificationModel
        function onCountChanged() {
            lockScreen.updateCategories()
        }
    }
    
    // Refresh categories when lock screen becomes visible
    // Update SessionStore to show lock icon in status bar
    onVisibleChanged: {
        if (visible) {
            Logger.info("LockScreen", "Lock screen visible - refreshing categories")
            lockScreen.updateCategories()
            SessionStore.isOnLockScreen = true
        } else {
            SessionStore.isOnLockScreen = false
        }
    }
    
    // Set initial state on component creation
    Component.onCompleted: {
        if (visible) {
            Logger.info("LockScreen", "Lock screen created visible - setting initial state")
            console.log("[LockScreen] SessionStore.isLocked =", SessionStore.isLocked)
            SessionStore.isOnLockScreen = true
            lockScreen.updateCategories()
        }
    }
    
    // Performance optimization: use layers for static content
    layer.enabled: true
    layer.smooth: true
    
    Item {
        id: lockContent
        anchors.fill: parent
        z: 1
        
        // Wallpaper with proper caching
        Image {
            anchors.fill: parent
            source: WallpaperStore.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            
            // GPU-accelerated layer
            layer.enabled: true
            layer.smooth: true
        }
        
        // Dismiss expanded notifications when tapping elsewhere
        MouseArea {
            anchors.fill: parent
            z: 1
            enabled: expandedCategory !== ""
            onClicked: {
                expandedCategory = ""
                resetIdleTimer()
                Logger.info("LockScreen", "Notifications dismissed")
            }
        }
        
        MarathonStatusBar {
            id: statusBar
            width: parent.width
            z: 5
        }
        
        // Time and Date - centered, or pushed up if unread notifications present
        Column {
            id: clockColumn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingSmall
            width: parent.width * 0.9  // Constrain width for children
            
            // Default state (centered)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(-80 * Constants.scaleFactor)
            
            onYChanged: Logger.info("LockScreen", "ClockColumn Y changed to: " + y)
            
            // States for layout transitions
            states: State {
                name: "hasNotifications"
                when: categoriesModel.count > 0
                AnchorChanges {
                    target: clockColumn
                    anchors.verticalCenter: undefined
                    anchors.top: parent.top
                }
                PropertyChanges {
                    target: clockColumn
                    anchors.topMargin: Math.round(80 * Constants.scaleFactor)
                    anchors.verticalCenterOffset: 0
                }
            }
            
            transitions: Transition {
                AnchorAnimation { duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { properties: "anchors.topMargin,anchors.verticalCenterOffset"; duration: 300; easing.type: Easing.OutCubic }
            }
            
            // GPU layer for text rendering
            layer.enabled: true
            layer.smooth: true
            
            Text {
                text: SystemStatusStore.timeString
                color: MColors.text
                font.pixelSize: Constants.fontSizeGigantic
                font.weight: Font.Thin
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
                
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#80000000"
                    shadowBlur: 0.3
                    shadowVerticalOffset: 2
                }
            }
            
            Text {
                text: SystemStatusStore.dateString
                color: MColors.text
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Normal
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.9
                renderType: Text.NativeRendering
                
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#80000000"
                    shadowBlur: 0.3
                    shadowVerticalOffset: 2
                }
            }
            
            // Media Player on Lock Screen
            Item {
                width: parent.width
                height: Constants.spacingMedium
                visible: lockScreenMediaPlayer.visible
            }
            
            MediaPlaybackManager {
                id: lockScreenMediaPlayer
                width: Math.min(parent.width, 400 * Constants.scaleFactor)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: hasMedia
                
                // Override background opacity for lock screen integration
                // Dark teal gradient background
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 191/255, 165/255, 0.15) } // MColors.marathonTealGlowTop approx
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.2) }
                }
                
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(0, 191/255, 165/255, 0.3) // MColors.marathonTealBorder approx
            }
        }
        
        // BB10-style Hub Notifications
        Item {
            id: notificationContainer
            // Anchor to clockColumn to ensure no overlap
            anchors.top: clockColumn.bottom
            anchors.topMargin: Constants.spacingMedium
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: categoriesModel.count > 0
            z: 10
            
            onYChanged: Logger.info("LockScreen", "NotificationContainer Y changed to: " + y)
            
            // Category icons on left edge
            Column {
                id: categoryIcons
                anchors.left: parent.left
                anchors.leftMargin: Constants.spacingMedium
                
                // Position relative to container
                anchors.top: categoriesModel.count <= 3 ? parent.top : undefined
                anchors.topMargin: categoriesModel.count <= 3 ? Math.round(20 * Constants.scaleFactor) : 0
                
                anchors.verticalCenter: categoriesModel.count > 3 ? parent.verticalCenter : undefined
                spacing: Constants.spacingLarge
                z: 100
                
                // Expose category count for clock positioning - NO LONGER NEEDED, using top level model
                // property alias unreadCategoryCount: categoriesModel.count
                
                Repeater {
                    model: categoriesModel
                    
                    delegate: Item {
                        width: Math.round(56 * Constants.scaleFactor)
                        height: Math.round(56 * Constants.scaleFactor)
                        
                        property string category: model.appId
                        property bool isActive: expandedCategory === category
                        
                        // Category icon
                        Rectangle {
                            id: categoryIconBg
                            width: Math.round(48 * Constants.scaleFactor)
                            height: Math.round(48 * Constants.scaleFactor)
                            radius: Math.round(24 * Constants.scaleFactor)
                            color: isActive ? MColors.elevated : MColors.surface
                            border.width: 1
                            border.color: isActive ? MColors.accent : "#3A3A3A"
                            anchors.centerIn: parent
                            antialiasing: true
                            
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#000000"
                                shadowOpacity: 0.5
                                shadowBlur: 0.5
                                shadowVerticalOffset: 2
                                shadowHorizontalOffset: 1
                            }
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                            
                            Behavior on border.color {
                                ColorAnimation { duration: 200 }
                            }
                            
                            Icon {
                                name: model.icon
                                size: 24
                                color: MColors.textPrimary
                                anchors.centerIn: parent
                            }
                            
                            // Badge count
                            Rectangle {
                                visible: model.count > 0
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: Math.round(-4 * Constants.scaleFactor)
                                anchors.topMargin: Math.round(-4 * Constants.scaleFactor)
                                width: Math.round(20 * Constants.scaleFactor)
                                height: Math.round(20 * Constants.scaleFactor)
                                radius: Math.round(10 * Constants.scaleFactor)
                                color: MColors.accent
                                border.width: 2
                                border.color: MColors.background
                                antialiasing: true
                                
                                Text {
                                    text: model.count
                                    color: "white"
                                    font.pixelSize: MTypography.sizeXSmall
                                    font.weight: Font.Bold
                                    anchors.centerIn: parent
                                    renderType: Text.NativeRendering
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticService.light()
                                resetIdleTimer()
                                if (expandedCategory === category) {
                                    expandedCategory = ""
                                    Logger.info("LockScreen", "Collapsed category: " + category)
                                } else {
                                    expandedCategory = category
                                    Logger.info("LockScreen", "Expanded category: " + category)
                                }
                            }
                        }
                    }
                }
            }
            
            Item {
                id: lineAndChevron
                visible: expandedCategory !== ""
                anchors.left: categoryIcons.right
                anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                anchors.top: categoryIcons.top
                anchors.bottom: categoryIcons.bottom
                width: Math.round(24 * Constants.scaleFactor)
                z: 50
                
                // Calculate chevron Y position based on active category
                function calculateChevronY() {
                    var activeIndex = -1
                    for (var i = 0; i < categoriesModel.count; i++) {
                        if (categoriesModel.get(i).appId === expandedCategory) {
                            activeIndex = i
                            break
                        }
                    }
                    
                    if (activeIndex === -1) activeIndex = 0
                    
                    // Account for item height (56px), spacing (20px), and centering
                    // Icon center: activeIndex * (56 + 20) + 28
                    // Chevron is 16px, center it: icon_center - 8 = activeIndex * 76 + 20
                    var itemHeight = Math.round(56 * Constants.scaleFactor)
                    var itemSpacing = Math.round(20 * Constants.scaleFactor)  // Constants.spacingLarge
                    var yPos = activeIndex * (itemHeight + itemSpacing) + Math.round(20 * Constants.scaleFactor)
                    Logger.info("LockScreen", "Chevron Y calculated: " + yPos + " for category: " + expandedCategory + " at index: " + activeIndex)
                    return yPos
                }
                
                Connections {
                    target: lockScreen
                    function onExpandedCategoryChanged() {
                        chevronCanvas.y = lineAndChevron.calculateChevronY()
                        topLineSegment.height = chevronCanvas.y  // Line goes right up to chevron
                        bottomLineSegment.anchors.topMargin = chevronCanvas.y + Math.round(16 * Constants.scaleFactor)  // Start right after chevron
                    }
                }
                
                // Top line segment (from top to chevron)
                Rectangle {
                    id: topLineSegment
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: Math.round(2 * Constants.scaleFactor)
                    height: Math.round(20 * Constants.scaleFactor)
                    color: "white"
                    opacity: 0.6
                    
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: 0.6
                        shadowBlur: 0.4
                        shadowVerticalOffset: 1
                        shadowHorizontalOffset: 1
                    }
                }
                
                // Chevron positioned at the active icon's vertical center
                Canvas {
                    id: chevronCanvas
                    anchors.right: topLineSegment.horizontalCenter  // Trailing edge aligned with line center
                    y: Math.round(20 * Constants.scaleFactor)
                    width: Math.round(12 * Constants.scaleFactor)
                    height: Math.round(16 * Constants.scaleFactor)
                    
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: 0.6
                        shadowBlur: 0.4
                        shadowVerticalOffset: 1
                        shadowHorizontalOffset: 1
                    }
                    
                    onYChanged: {
                        Logger.info("LockScreen", "Chevron Y changed to: " + y)
                        requestPaint()
                    }
                    
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "white"
                        ctx.lineWidth = 2
                        ctx.globalAlpha = 0.6
                        ctx.beginPath()
                        // Draw left-pointing chevron (right edge is the trailing edge)
                        ctx.moveTo(width, 0)
                        ctx.lineTo(0, height / 2)
                        ctx.lineTo(width, height)
                        ctx.stroke()
                    }
                }
                
                // Bottom line segment (from chevron to bottom)
                Rectangle {
                    id: bottomLineSegment
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(36 * Constants.scaleFactor)
                    anchors.bottom: parent.bottom
                    width: Math.round(2 * Constants.scaleFactor)
                    color: "white"
                    opacity: 0.6
                    
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: 0.6
                        shadowBlur: 0.4
                        shadowVerticalOffset: 1
                        shadowHorizontalOffset: 1
                    }
                }
            }
            
            // Notification list for active category - positioned to the right of line, aligned with icons
            ListView {
                id: notificationList
                visible: expandedCategory !== ""
                anchors.left: lineAndChevron.right
                anchors.leftMargin: Math.round(4 * Constants.scaleFactor)
                anchors.right: parent.right
                anchors.rightMargin: Math.round(16 * Constants.scaleFactor)
                anchors.top: categoryIcons.top
                anchors.topMargin: Math.round(-8 * Constants.scaleFactor)
                height: Math.min(count * Math.round(80 * Constants.scaleFactor), parent.height * 0.5)
                spacing: Constants.spacingSmall
                clip: true
                z: 40
                
                model: ListModel {
                    id: filteredNotificationsModel
                }
                
                // Update filtered notifications when category changes
                onVisibleChanged: {
                    if (visible) updateFilteredNotifications()
                }
                
                Connections {
                    target: lockScreen
                    function onExpandedCategoryChanged() {
                        notificationList.updateFilteredNotifications()
                    }
                }
                
                Connections {
                    target: NotificationModel
                    function onCountChanged() {
                        if (notificationList.visible) {
                            notificationList.updateFilteredNotifications()
                        }
                    }
                }
                
                function updateFilteredNotifications() {
                    filteredNotificationsModel.clear()
                    
                    if (expandedCategory === "") return
                    
                    for (var i = 0; i < NotificationModel.rowCount(); i++) {
                        var idx = NotificationModel.index(i, 0)
                        var isRead = NotificationModel.data(idx, Shell.NotificationRoles.IsReadRole) || false
                        
                        // Skip read notifications
                        if (isRead) continue
                        
                        var appId = NotificationModel.data(idx, Shell.NotificationRoles.AppIdRole) || "other"
                        
                        if (appId === expandedCategory) {
                            filteredNotificationsModel.append({
                                "notifId": NotificationModel.data(idx, Shell.NotificationRoles.IdRole),
                                "title": NotificationModel.data(idx, Shell.NotificationRoles.TitleRole),
                                "body": NotificationModel.data(idx, Shell.NotificationRoles.BodyRole),
                                "timestamp": NotificationModel.data(idx, Shell.NotificationRoles.TimestampRole)
                            })
                        }
                    }
                }
                
                delegate: Item {
                    width: notificationList.width
                    height: Math.round(70 * Constants.scaleFactor)
                    
                    Row {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingMedium
                        spacing: 0
                        
                        // Left content
                        Column {
                            width: parent.width - timestampText.width - Constants.spacingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Math.round(4 * Constants.scaleFactor)
                            
                            Text {
                                text: model.title || ""
                                color: "white"
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.Bold
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                                renderType: Text.NativeRendering
                                
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#80000000"
                                    shadowBlur: 0.4
                                    shadowVerticalOffset: 2
                                }
                            }
                            
                            Text {
                                text: model.body || ""
                                color: "#E0FFFFFF"
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                                renderType: Text.NativeRendering
                                
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#80000000"
                                    shadowBlur: 0.3
                                    shadowVerticalOffset: 1
                                }
                            }
                        }
                        
                        // Timestamp on right
                        Text {
                            id: timestampText
                            text: Qt.formatTime(new Date(model.timestamp), "h:mm AP")
                            color: "#B0FFFFFF"
                            font.pixelSize: MTypography.sizeSmall
                            font.family: MTypography.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#80000000"
                                shadowBlur: 0.3
                                shadowVerticalOffset: 1
                            }
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light()
                            resetIdleTimer()
                            Logger.info("LockScreen", "Notification tapped: " + model.title)
                            
                            // Get the full notification data
                            var notifId = model.notifId || 0
                            var appId = ""
                            
                            // Find the appId from the original notification
                            for (var i = 0; i < NotificationModel.rowCount(); i++) {
                                var idx = NotificationModel.index(i, 0)
                                var id = NotificationModel.data(idx, Shell.NotificationRoles.IdRole)
                                if (id === notifId) {
                                    appId = NotificationModel.data(idx, Shell.NotificationRoles.AppIdRole) || ""
                                    break
                                }
                            }
                            
                            // Emit signal with notification info
                            notificationTapped(notifId, appId, model.title)
                        }
                    }
                }
            }
        }
        
        // Use actual BottomBar component
        MarathonBottomBar {
            id: lockScreenBottomBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            showPageIndicators: false
            z: 10
            
            onAppLaunched: (app) => {
                if (app.id === "phone") {
                    HapticService.medium()
                    Logger.info("LockScreen", "Phone quick action tapped")
                    phoneLaunched()
                } else if (app.id === "camera") {
                    HapticService.medium()
                    Logger.info("LockScreen", "Camera quick action tapped")
                    cameraLaunched()
                }
            }
        }
        
        // Swipe up indicator - vertically centered with bottom bar icons
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: lockScreenBottomBar.verticalCenter
            spacing: Math.round(4 * Constants.scaleFactor)
            opacity: 0.7
            z: 11
            
            Icon {
                name: "chevron-up"
                size: Math.round(24 * Constants.scaleFactor)
                color: "white"
                anchors.horizontalCenter: parent.horizontalCenter
                
                SequentialAnimation on y {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { to: -6; duration: 800; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0; duration: 800; easing.type: Easing.InOutQuad }
                }
            }
            
            Text {
                text: "Swipe up to unlock"
                color: "white"
                font.pixelSize: MTypography.sizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
            }
        }
        
        // Fade out effect as user swipes
        opacity: 1.0 - Math.pow(swipeProgress, 0.7)
        
        Behavior on opacity {
            enabled: swipeProgress > 0.5
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }
    
    // No overlay needed - content underneath (PIN/launcher) is already visible
    
    // Optimized touch handling with momentum
    MouseArea {
        anchors.fill: parent
        z: 0
        propagateComposedEvents: true
        
        property real startY: 0
        property real lastY: 0
        property real velocity: 0
        property bool isDragging: false
        property real lastTime: 0
        
        onPressed: (mouse) => {
            startY = mouse.y
            lastY = mouse.y
            velocity = 0
            isDragging = false
            lastTime = Date.now()
            resetIdleTimer()
            // Don't reject here - we need to track the gesture to determine if it's a swipe or tap
        }
        
        onPositionChanged: (mouse) => {
            const deltaY = lastY - mouse.y
            const now = Date.now()
            const deltaTime = now - lastTime
            
            if (deltaTime > 0) {
                velocity = deltaY / deltaTime
            }
            
            lastY = mouse.y
            lastTime = now
            
            // Allow swipes from anywhere on the screen (including swipe indicator area)
            const totalDelta = startY - mouse.y
            
            if (totalDelta > 10) {
                isDragging = true
                // Once we detect dragging, stop propagating to notification taps
                mouse.accepted = true
            }
            
            if (isDragging) {
                // Super easy: only need to swipe 15% of screen height
                const threshold = height * 0.15
                swipeProgress = Math.max(0, Math.min(1.0, totalDelta / threshold))
                
                // Haptic feedback at 50% and 100%
                if (swipeProgress > 0.5 && swipeProgress < 0.55) {
                    HapticService.light()
                }
            }
        }
        
        onReleased: (mouse) => {
            if (isDragging) {
                // Very low threshold: 20% progress OR positive velocity
                if (swipeProgress > 0.20 || velocity > 0.5) {
                    // Animate to complete
                    swipeProgress = 1.0
                    HapticService.medium()
                    unlockTimer.start()
                } else {
                    // Snap back
                    swipeProgress = 0
                    expandedCategory = ""
                }
            } else {
                // Was a tap, not a swipe - notifications will handle it via their MouseAreas
                Logger.info("LockScreen", "Tap detected (no drag), x=" + mouse.x + ", y=" + mouse.y)
            }
            
            isDragging = false
            velocity = 0
        }
    }
    
    // Smooth spring animation for swipe progress
    Behavior on swipeProgress {
        enabled: swipeProgress < 1.0
        SmoothedAnimation { 
            velocity: 8
            duration: 150
        }
    }
    
    Timer {
        id: unlockTimer
        interval: 100
        onTriggered: {
            Logger.state("LockScreen", "unlocked", "dissolve complete")
            unlockRequested()
        }
    }
}

