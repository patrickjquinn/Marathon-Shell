import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
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
    signal notificationTapped(string id)
    
    property real swipeProgress: 0.0
    property string expandedNotificationId: ""
    
    // Hide lockscreen when fully swiped
    visible: swipeProgress < 0.99
    
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
            enabled: expandedNotificationId !== ""
            onClicked: {
                expandedNotificationId = ""
                Logger.info("LockScreen", "Notifications dismissed")
            }
        }
        
        MarathonStatusBar {
            id: statusBar
            width: parent.width
            z: 5
        }
        
        // Time and Date - centered
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(-80 * Constants.scaleFactor)
            spacing: Constants.spacingSmall
            
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
        }
        
        // Notifications - left side
        Column {
            anchors.left: parent.left
            anchors.leftMargin: Constants.spacingLarge
            anchors.verticalCenter: parent.verticalCenter
            spacing: Constants.spacingMedium
            z: 10
            
            Repeater {
                model: NotificationModel
                
                delegate: Item {
                    width: expandedNotificationId === model.id ? Math.round(300 * Constants.scaleFactor) : Math.round(48 * Constants.scaleFactor)
                    height: Math.round(48 * Constants.scaleFactor)
                    visible: index < 4
                    z: 10
                    
                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        color: expandedNotificationId === model.id ? MColors.surface : "transparent"
                        radius: Constants.borderRadiusSharp
                        antialiasing: true
                        z: 10
                        
                        // GPU layer for notification cards
                        layer.enabled: expandedNotificationId === model.id
                        layer.smooth: true
                        
                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                width: Constants.touchTargetMinimum
                                height: Constants.touchTargetMinimum
                                radius: Math.round(20 * Constants.scaleFactor)
                                color: expandedNotificationId === model.id ? MColors.elevated : "transparent"
                                border.width: expandedNotificationId === model.id ? 0 : Constants.borderWidthThin
                                border.color: MColors.border
                                anchors.verticalCenter: parent.verticalCenter
                                antialiasing: true
                                
                                Behavior on color {
                                    ColorAnimation { duration: 200 }
                                }
                                Behavior on border.width {
                                    NumberAnimation { duration: 200 }
                                }
                                
                                Icon {
                                    name: model.icon || "bell"
                                    size: 24
                                    color: MColors.textPrimary
                                    anchors.centerIn: parent
                                }
                                
                                Rectangle {
                                    visible: !model.isRead
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: Math.round(-2 * Constants.scaleFactor)
                                    anchors.topMargin: Math.round(-2 * Constants.scaleFactor)
                                    width: Math.round(10 * Constants.scaleFactor)
                                    height: Math.round(10 * Constants.scaleFactor)
                                    radius: Math.round(5 * Constants.scaleFactor)
                                    color: MColors.accent
                                    antialiasing: true
                                }
                            }
                            
                            Column {
                                visible: expandedNotificationId === model.id
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Math.round(68 * Constants.scaleFactor)
                                spacing: Math.round(2 * Constants.scaleFactor)
                                
                                Text {
                                    text: model.title || ""
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: Font.Bold
                                    font.family: MTypography.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                    renderType: Text.NativeRendering
                                }
                                
                                Text {
                                    text: model.body || ""
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeXSmall
                                    font.family: MTypography.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                    renderType: Text.NativeRendering
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            z: 20
                            preventStealing: true
                            
                            onPressed: {
                                Logger.info("LockScreen", "Notification MouseArea pressed: " + model.title)
                            }
                            
                            onClicked: {
                                HapticService.light()
                                Logger.info("LockScreen", "Notification clicked: " + model.title)
                                if (expandedNotificationId === model.id) {
                                    expandedNotificationId = ""
                                    Logger.info("LockScreen", "Notification dismissed: " + model.title)
                                } else {
                                    expandedNotificationId = model.id
                                    Logger.info("LockScreen", "Notification expanded: " + model.title)
                                }
                            }
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
                    expandedNotificationId = ""
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
