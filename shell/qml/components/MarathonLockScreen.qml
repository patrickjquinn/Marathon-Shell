import QtQuick
import "../theme"
import "../stores"
import "."

// BlackBerry 10 Lock Screen - Clean, minimal, beautiful
Rectangle {
    id: lockScreen
    anchors.fill: parent
    
    signal unlockRequested()  // Emitted when user swipes up
    signal cameraLaunched()
    signal hubOpened()
    
    property real swipeProgress: 0.0  // 0.0 = locked, 1.0 = unlocking
    property int currentNotificationPage: 0
    property int totalNotificationPages: 3  // Mock data for now
    
    // Wallpaper background
    Image {
        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
        
        // Fade out as unlock progresses
        opacity: 1.0 - (swipeProgress * 0.3)
        
        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Status bar at top
    MarathonStatusBar {
        id: statusBar
        width: parent.width
        z: 5
        opacity: 1.0 - (swipeProgress * 0.5)
    }
    
    // Large Date Display (center-top)
    Text {
        id: dateDisplay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.25
        text: SystemStatusStore.dateString
        color: WallpaperStore.isDark ? Colors.text : "#FFFFFF"
        font.pixelSize: 48
        font.weight: Font.Light
        z: 2
        
        // Fade and move up slightly as unlock progresses
        opacity: 1.0 - swipeProgress
        transform: Translate { y: -swipeProgress * 50 }
        
        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Bottom UI Container
    Item {
        id: bottomUI
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 140
        z: 3
        
        // Fade out as unlock progresses
        opacity: 1.0 - swipeProgress
        
        // Hub/Messages Shortcut (bottom left)
        Rectangle {
            id: hubShortcut
            anchors.left: parent.left
            anchors.leftMargin: 40
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: 64
            height: 64
            radius: 32
            color: Qt.rgba(1, 1, 1, 0.2)
            border.color: Qt.rgba(1, 1, 1, 0.4)
            border.width: 1
            
            Image {
                source: "qrc:/images/icons/lucide/bell.svg"
                width: 32
                height: 32
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    console.log("📨 Hub shortcut tapped")
                    hubOpened()
                }
            }
        }
        
        // Page Indicators (center)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 52
            spacing: 12
            
            Repeater {
                model: totalNotificationPages
                
                Rectangle {
                    width: index === currentNotificationPage ? 10 : 8
                    height: index === currentNotificationPage ? 10 : 8
                    radius: width / 2
                    color: index === currentNotificationPage ? Colors.text : Qt.rgba(1, 1, 1, 0.4)
                    border.color: Qt.rgba(1, 1, 1, 0.6)
                    border.width: 1
                    
                    Behavior on width { NumberAnimation { duration: 200 } }
                    Behavior on height { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }
        
        // Camera Shortcut (bottom right)
        Rectangle {
            id: cameraShortcut
            anchors.right: parent.right
            anchors.rightMargin: 40
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: 64
            height: 64
            radius: 32
            color: Qt.rgba(1, 1, 1, 0.2)
            border.color: Qt.rgba(1, 1, 1, 0.4)
            border.width: 1
            
            Image {
                source: "qrc:/images/camera.svg"
                width: 36
                height: 36
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    console.log("📷 Camera shortcut tapped")
                    cameraLaunched()
                }
            }
        }
    }
    
    // Swipe Up Unlock Gesture Area
    MouseArea {
        id: swipeArea
        anchors.fill: parent
        z: 1
        
        property real startY: 0
        property real startTime: 0
        property bool isValidSwipe: false
        
        onPressed: (mouse) => {
            startY = mouse.y
            startTime = Date.now()
            isValidSwipe = mouse.y > parent.height * 0.5  // Only accept swipes from bottom half
            console.log("🔒 Lock screen touch started at:", mouse.y)
        }
        
        onPositionChanged: (mouse) => {
            if (!isValidSwipe) return
            
            var dragDistance = startY - mouse.y
            if (dragDistance > 0) {
                // Calculate progress (0.0 to 1.0)
                swipeProgress = Math.min(1.0, dragDistance / (parent.height * 0.6))
                console.log("🔒 Swipe progress:", swipeProgress.toFixed(2))
            }
        }
        
        onReleased: (mouse) => {
            if (!isValidSwipe) {
                swipeProgress = 0
                return
            }
            
            var dragDistance = startY - mouse.y
            var velocity = dragDistance / (Date.now() - startTime) * 1000  // pixels per second
            
            console.log("🔒 Released. Progress:", swipeProgress.toFixed(2), "Velocity:", velocity.toFixed(0))
            
            // Threshold: 40% of screen OR fast swipe (> 800 px/s)
            if (swipeProgress > 0.4 || velocity > 800) {
                // Complete unlock animation
                swipeProgress = 1.0
                console.log("✅ Unlock threshold met - requesting unlock")
                
                // Emit unlock signal after animation completes
                unlockTimer.start()
            } else {
                // Snap back to locked
                swipeProgress = 0
                console.log("↩️ Snap back to locked")
            }
            
            startY = 0
            isValidSwipe = false
        }
        
        onCanceled: {
            swipeProgress = 0
            startY = 0
            isValidSwipe = false
        }
    }
    
    // Spring animation for snap-back
    Behavior on swipeProgress {
        enabled: swipeProgress < 1.0
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }
    
    // Timer to emit unlock signal after animation
    Timer {
        id: unlockTimer
        interval: 200
        repeat: false
        onTriggered: {
            console.log("🔓 Emitting unlockRequested signal")
            unlockRequested()
        }
    }
    
    // Force time updates
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            // Force refresh
            lockScreen.visible = lockScreen.visible
        }
    }
}
