import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: navBar
    height: Constants.navBarHeight
    color: MColors.backgroundDark
    
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.borderWidthThin
        color: MColors.borderOuter
    }
    
    signal swipeLeft()
    signal swipeRight()
    signal swipeBack()
    signal shortSwipeUp()
    signal longSwipeUp()
    signal minimizeApp()
    signal startPageTransition()
    
    property real startX: 0
    property real startY: 0
    property real currentX: 0
    property real currentY: 0
    property real shortSwipeThreshold: Constants.gestureSwipeShort
    property real longSwipeThreshold: Constants.gestureSwipeLong
    
    Rectangle {
        id: indicator
        width: Constants.cardBannerHeight
        height: Constants.spacingXSmall
        radius: Constants.borderRadiusSharp
        color: MColors.text
        opacity: 0.9
        antialiasing: Constants.enableAntialiasing
        
        property real targetX: parent.width / 2 - width / 2
        property real targetY: parent.height / 2 - height / 2
        property real dragX: currentX * 0.3
        property real dragY: currentY * 0.3
        
        x: root.targetX + dragX
        y: root.targetY - dragY
        
        Behavior on x {
            enabled: !navMouseArea.pressed
            SpringAnimation {
                spring: 3
                damping: 0.3
                epsilon: 0.25
            }
        }
        
        Behavior on y {
            enabled: !navMouseArea.pressed
            SpringAnimation {
                spring: 3
                damping: 0.3
                epsilon: 0.25
            }
        }
    }
    
    property bool isAppOpen: false
    property real gestureProgress: 0
    
    MouseArea {
        id: navMouseArea
        anchors.fill: parent
        anchors.topMargin: 0
        z: 200
        
        property real velocityX: 0
        property real lastX: 0
        property real lastTime: 0
        property bool isVerticalGesture: false
        
        onPressed: (mouse) => {
            root.startX = mouse.x
            root.startY = mouse.y
            root.lastX = mouse.x
            root.lastTime = Date.now()
            root.velocityX = 0
            root.isVerticalGesture = false
        }
        
        onPositionChanged: (mouse) => {
            var now = Date.now()
            var dt = now - root.lastTime
            if (dt > 0) {
                root.velocityX = (mouse.x - root.lastX) / dt * 1000
            }
            root.lastX = mouse.x
            root.lastTime = now
            
            var diffX = mouse.x - root.startX
            var diffY = root.startY - mouse.y
            
            if (Math.abs(diffY) > Math.abs(diffX) && Math.abs(diffY) > 10) {
                if (!root.isVerticalGesture) {
                }
                root.isVerticalGesture = true
            }
            
            if (root.isVerticalGesture) {
                root.currentY = Math.max(0, diffY)
                root.currentX = 0
                
                // Drag Quick Settings up when open
                if (UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) {
                    if (!UIStore.quickSettingsDragging) {
                        UIStore.quickSettingsDragging = true
                    }
                    var newHeight = UIStore.quickSettingsHeight - diffY
                    var maxHeight = UIStore.shellRef ? UIStore.shellRef.maxQuickSettingsHeight : 1000
                    UIStore.quickSettingsHeight = Math.max(0, Math.min(maxHeight, newHeight))
                    root.startY = mouse.y  // Update startY for continuous tracking
                } else if (root.isAppOpen) {
                    var oldProgress = root.gestureProgress
                    root.gestureProgress = Math.min(1.0, diffY / 250)
                    if (oldProgress <= 0.15 && root.gestureProgress > 0.15) {
                        startPageTransition()
                    }
                }
            } else {
                root.currentX = diffX
                root.currentY = 0
                root.gestureProgress = 0
            }
        }
        
        onReleased: (mouse) => {
            var diffX = mouse.x - root.startX
            var diffY = root.startY - mouse.y
            
            Logger.gesture("NavBar", "released", {diffX: diffX, diffY: diffY, velocity: root.velocityX, isAppOpen: isAppOpen, quickSettingsOpen: UIStore.quickSettingsOpen})
            
            // Snap Quick Settings open/closed based on threshold
            if ((UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) && root.isVerticalGesture) {
                Logger.info("NavBar", "Quick Settings height: " + UIStore.quickSettingsHeight)
                UIStore.quickSettingsDragging = false
                var threshold = UIStore.shellRef ? UIStore.shellRef.quickSettingsThreshold : 400
                if (UIStore.quickSettingsHeight > threshold) {
                    UIStore.openQuickSettings()
                } else {
                    UIStore.closeQuickSettings()
                }
                // Reset gesture state
                root.startX = 0
                root.startY = 0
                root.velocityX = 0
                root.isVerticalGesture = false
                root.currentX = 0
                root.currentY = 0
                root.gestureProgress = 0
                return
            }
            
            // Close Search with upward gesture
            if (UIStore.searchOpen && root.isVerticalGesture && diffY > 60) {
                Logger.info("NavBar", "Closing Search with upward gesture")
                UIStore.closeSearch()
                root.startX = 0
                root.startY = 0
                root.velocityX = 0
                root.isVerticalGesture = false
                root.currentX = 0
                root.currentY = 0
                root.gestureProgress = 0
                return
            }
            
            if (root.isVerticalGesture && diffY > 30) {
                if (root.isAppOpen && (diffY > 100 || gestureProgress > 0.4)) {
                    Logger.info("NavBar", "⬆️ MINIMIZE GESTURE - diffY: " + diffY + ", gestureProgress: " + root.gestureProgress)
                    minimizeApp()
                    gestureProgressResetTimer.start()
                } else if (diffY > root.longSwipeThreshold) {
                    Logger.info("NavBar", "Long swipe up - Task switcher")
                    longSwipeUp()
                    root.currentX = 0
                    root.currentY = 0
                    root.gestureProgress = 0
                } else if (diffY > root.shortSwipeThreshold) {
                    Logger.info("NavBar", "Short swipe up - Go home")
                    shortSwipeUp()
                    root.currentX = 0
                    root.currentY = 0
                    root.gestureProgress = 0
                }
            } else if (!root.isVerticalGesture && (Math.abs(diffX) > 50 || Math.abs(root.velocityX) > 500)) {
                if (diffX < 0 || root.velocityX < 0) {
                    Logger.gesture("NavBar", "swipeLeft", {velocity: root.velocityX, isAppOpen: isAppOpen})
                    if (root.isAppOpen) {
                        // When app is open, swipe left = back gesture
                        swipeBack()
                    } else {
                        // Otherwise, navigate pages left
                        swipeLeft()
                    }
                } else {
                    Logger.gesture("NavBar", "swipeRight", {velocity: root.velocityX, isAppOpen: isAppOpen, diffX: diffX})
                    swipeRight()
                }
                root.currentX = 0
                root.currentY = 0
                root.gestureProgress = 0
            } else {
                // Cancelled gesture - reset immediately
                Logger.info("NavBar", "🔴 GESTURE CANCELLED - diffX: " + diffX + ", diffY: " + diffY)
                root.currentX = 0
                root.currentY = 0
                root.gestureProgress = 0
            }
            
            root.startX = 0
            root.startY = 0
            root.velocityX = 0
            root.isVerticalGesture = false
        }
    }
    
    Timer {
        id: gestureProgressResetTimer
        interval: 300
        onTriggered: {
            Logger.info("NavBar", "⏱️ GESTURE PROGRESS RESET")
            navBar.gestureProgress = 0
            navBar.currentX = 0
            navBar.currentY = 0
        }
    }
    
    Behavior on gestureProgress {
        enabled: !navMouseArea.pressed && !gestureProgressResetTimer.running
        SpringAnimation {
            spring: 2.5
            damping: 0.5
            epsilon: 0.01
        }
    }
}

