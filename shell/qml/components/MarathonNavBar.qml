import QtQuick
import MarathonOS.Shell

Rectangle {
    id: navBar
    height: 32
    color: Colors.backgroundDark
    
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Colors.borderLight
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
    property int shortSwipeThreshold: 80
    property int longSwipeThreshold: 150
    
    Rectangle {
        id: indicator
        width: 100
        height: 4
        radius: 2
        color: Colors.text
        opacity: 0.9
        
        property real targetX: parent.width / 2 - width / 2
        property real targetY: parent.height / 2 - height / 2
        property real dragX: currentX * 0.3
        property real dragY: currentY * 0.3
        
        x: targetX + dragX
        y: targetY - dragY
        
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
            startX = mouse.x
            startY = mouse.y
            lastX = mouse.x
            lastTime = Date.now()
            velocityX = 0
            isVerticalGesture = false
        }
        
        onPositionChanged: (mouse) => {
            var now = Date.now()
            var dt = now - lastTime
            if (dt > 0) {
                velocityX = (mouse.x - lastX) / dt * 1000
            }
            lastX = mouse.x
            lastTime = now
            
            var diffX = mouse.x - startX
            var diffY = startY - mouse.y
            
            if (Math.abs(diffY) > Math.abs(diffX) && Math.abs(diffY) > 10) {
                if (!isVerticalGesture) {
                }
                isVerticalGesture = true
            }
            
            if (isVerticalGesture) {
                currentY = Math.max(0, diffY)
                currentX = 0
                if (isAppOpen) {
                    var oldProgress = gestureProgress
                    gestureProgress = Math.min(1.0, diffY / 250)
                    if (oldProgress <= 0.15 && gestureProgress > 0.15) {
                        startPageTransition()
                    }
                }
            } else {
                currentX = diffX
                currentY = 0
                gestureProgress = 0
            }
        }
        
        onReleased: (mouse) => {
            var diffX = mouse.x - startX
            var diffY = startY - mouse.y
            
            Logger.gesture("NavBar", "released", {diffX: diffX, diffY: diffY, velocity: velocityX, isAppOpen: isAppOpen})
            
            if (isVerticalGesture && diffY > 30) {
                if (isAppOpen && diffY > 60) {
                    Logger.info("NavBar", "⬆️ MINIMIZE GESTURE - diffY: " + diffY + ", gestureProgress: " + gestureProgress)
                    minimizeApp()
                    // Keep gestureProgress for the transition animation
                    gestureProgressResetTimer.start()
                } else if (diffY > longSwipeThreshold) {
                    Logger.info("NavBar", "Long swipe up - Task switcher")
                    longSwipeUp()
                    // Reset immediately for non-app gestures
                    currentX = 0
                    currentY = 0
                    gestureProgress = 0
                } else if (diffY > shortSwipeThreshold) {
                    Logger.info("NavBar", "Short swipe up - Go home")
                    shortSwipeUp()
                    // Reset immediately for non-app gestures
                    currentX = 0
                    currentY = 0
                    gestureProgress = 0
                }
            } else if (!isVerticalGesture && (Math.abs(diffX) > 50 || Math.abs(velocityX) > 500)) {
                if (diffX > 0 || velocityX > 0) {
                    Logger.gesture("NavBar", "swipeRight", {velocity: velocityX, isAppOpen: isAppOpen})
                    if (isAppOpen) {
                        // When app is open, swipe right = back gesture
                        swipeBack()
                    } else {
                        // Otherwise, navigate pages
                        swipeRight()
                    }
                } else {
                    Logger.gesture("NavBar", "swipeLeft", {velocity: velocityX})
                    swipeLeft()
                }
                currentX = 0
                currentY = 0
                gestureProgress = 0
            } else {
                // Cancelled gesture - reset immediately
                Logger.info("NavBar", "🔴 GESTURE CANCELLED - diffX: " + diffX + ", diffY: " + diffY)
                currentX = 0
                currentY = 0
                gestureProgress = 0
            }
            
            startX = 0
            startY = 0
            velocityX = 0
            isVerticalGesture = false
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

