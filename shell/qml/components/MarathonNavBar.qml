import QtQuick
import "../theme"

Rectangle {
    id: navBar
    height: 20
    color: "#000000"
    
    signal swipeLeft()
    signal swipeRight()
    signal shortSwipeUp()
    signal longSwipeUp()
    
    property real startX: 0
    property real startY: 0
    property real currentX: 0
    property int shortSwipeThreshold: 30
    property int longSwipeThreshold: 80
    
    Rectangle {
        id: indicator
        anchors.centerIn: parent
        width: 80
        height: 2
        radius: 1
        color: "#FFFFFF"
        opacity: 0.8
        
        x: parent.width / 2 - width / 2 + currentX
        
        Behavior on x {
            enabled: !navMouseArea.pressed
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }
    
    MouseArea {
        id: navMouseArea
        anchors.fill: parent
        
        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
        }
        
        onPositionChanged: (mouse) => {
            var diffX = mouse.x - startX
            var diffY = startY - mouse.y
            
            if (Math.abs(diffY) > Math.abs(diffX)) {
                // Vertical swipe
            } else {
                // Horizontal swipe - move indicator
                currentX = diffX
            }
        }
        
        onReleased: (mouse) => {
            var diffX = mouse.x - startX
            var diffY = startY - mouse.y
            
            if (Math.abs(diffY) > Math.abs(diffX)) {
                // Vertical
                if (diffY > longSwipeThreshold) {
                    longSwipeUp()
                } else if (diffY > shortSwipeThreshold) {
                    shortSwipeUp()
                }
            } else if (Math.abs(diffX) > 50) {
                // Horizontal
                if (diffX > 0) {
                    swipeRight()
                } else {
                    swipeLeft()
                }
            }
            
            currentX = 0
            startX = 0
            startY = 0
        }
    }
}

