import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
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
                model: Math.min(NotificationModel.count, 4)
                
                Item {
                    width: expandedNotificationId === modelData.id ? Math.round(300 * Constants.scaleFactor) : Math.round(48 * Constants.scaleFactor)
                    height: Math.round(48 * Constants.scaleFactor)
                    
                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        color: expandedNotificationId === modelData.id ? MColors.surface : "transparent"
                        radius: Constants.borderRadiusSharp
                        antialiasing: true
                        
                        // GPU layer for notification cards
                        layer.enabled: expandedNotificationId === modelData.id
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
                                color: expandedNotificationId === modelData.id ? MColors.surface2 : "transparent"
                                border.width: expandedNotificationId === modelData.id ? 0 : Constants.borderWidthThin
                                border.color: MColors.borderOuter
                                anchors.verticalCenter: parent.verticalCenter
                                antialiasing: true
                                
                                Behavior on color {
                                    ColorAnimation { duration: 200 }
                                }
                                Behavior on border.width {
                                    NumberAnimation { duration: 200 }
                                }
                                
                                Image {
                                    source: modelData.icon
                                    width: Math.round(24 * Constants.scaleFactor)
                                    height: Math.round(24 * Constants.scaleFactor)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    anchors.centerIn: parent
                                }
                                
                                Rectangle {
                                    visible: !modelData.read
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: Math.round(-4 * Constants.scaleFactor)
                                    anchors.topMargin: Math.round(-4 * Constants.scaleFactor)
                                    width: Math.round(18 * Constants.scaleFactor)
                                    height: Math.round(18 * Constants.scaleFactor)
                                    radius: Constants.borderRadiusSharp
                                    color: MColors.error
                                    antialiasing: true
                                    
                                    Text {
                                        text: "1"
                                        color: MColors.text
                                        font.pixelSize: MTypography.sizeXSmall
                                        font.weight: Font.Bold
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                            
                            Column {
                                visible: expandedNotificationId === modelData.id
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Math.round(68 * Constants.scaleFactor)
                                spacing: Math.round(2 * Constants.scaleFactor)
                                
                                Text {
                                    text: modelData.title
                                    color: MColors.text
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    width: parent.width
                                    renderType: Text.NativeRendering
                                }
                                
                                Text {
                                    text: modelData.subtitle
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeXSmall
                                    elide: Text.ElideRight
                                    width: parent.width
                                    renderType: Text.NativeRendering
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            z: 100
                            
                            property var notification: modelData
                            
                            onClicked: {
                                if (expandedNotificationId === notification.id) {
                                    expandedNotificationId = ""
                                    Logger.info("LockScreen", "Notification dismissed: " + notification.title)
                                } else {
                                    expandedNotificationId = notification.id
                                    Logger.info("LockScreen", "Notification expanded: " + notification.title)
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
        z: 5
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
            
            // Let notifications handle their own clicks
            if (mouse.y > height * 0.3 && mouse.y < height * 0.7 && mouse.x < 350) {
                mouse.accepted = false
                return
            }
            // Bottom bar buttons now handle their own events with propagateComposedEvents
            // No need to block anything - swipes work everywhere including bottom bar
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
