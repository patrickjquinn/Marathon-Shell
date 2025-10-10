import QtQuick
import "../theme"

Item {
    id: gestureHandler
    
    signal bottomSwipeStarted()
    signal bottomSwipeProgress(real progress)
    signal bottomSwipeReleased(bool committed)
    
    signal leftSwipeStarted()
    signal leftSwipeProgress(real progress)
    signal leftSwipeReleased(bool committed)
    
    signal rightSwipeStarted()
    signal rightSwipeProgress(real progress)
    signal rightSwipeReleased(bool committed)
    
    property real startX: 0
    property real startY: 0
    property string activeGesture: ""
    
    MouseArea {
        anchors.fill: parent
        preventStealing: false
        propagateComposedEvents: true
        
        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            
            if (mouse.y > height - Theme.peekThreshold) {
                activeGesture = "bottom"
                bottomSwipeStarted()
                mouse.accepted = true
            } else if (mouse.x < Theme.edgeGestureWidth) {
                activeGesture = "left"
                leftSwipeStarted()
                mouse.accepted = true
            } else if (mouse.x > width - Theme.edgeGestureWidth) {
                activeGesture = "right"
                rightSwipeStarted()
                mouse.accepted = true
            } else {
                activeGesture = ""
                mouse.accepted = false
            }
        }
        
        onPositionChanged: (mouse) => {
            if (activeGesture === "bottom") {
                var dragY = startY - mouse.y
                var progress = Math.max(0, Math.min(1, dragY / Theme.commitThreshold))
                bottomSwipeProgress(progress)
                mouse.accepted = true
            } else if (activeGesture === "left") {
                var dragX = mouse.x - startX
                var progress = Math.max(0, Math.min(1, dragX / Theme.hubWidth))
                leftSwipeProgress(progress)
                mouse.accepted = true
            } else if (activeGesture === "right") {
                var dragX = startX - mouse.x
                var progress = Math.max(0, Math.min(1, dragX / 200))
                rightSwipeProgress(progress)
                mouse.accepted = true
            }
        }
        
        onReleased: (mouse) => {
            if (activeGesture === "bottom") {
                var dragY = startY - mouse.y
                var committed = dragY > Theme.commitThreshold
                bottomSwipeReleased(committed)
            } else if (activeGesture === "left") {
                var dragX = mouse.x - startX
                var committed = dragX > Theme.hubWidth * 0.5
                leftSwipeReleased(committed)
            } else if (activeGesture === "right") {
                var dragX = startX - mouse.x
                var committed = dragX > 100
                rightSwipeReleased(committed)
            }
            activeGesture = ""
            mouse.accepted = true
        }
    }
}

