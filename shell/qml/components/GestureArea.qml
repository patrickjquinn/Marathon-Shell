import QtQuick
import "../theme"

MouseArea {
    id: gestureArea
    
    signal peekStarted()
    signal peekProgress(real progress)
    signal peekReleased(bool committed)
    
    property real startY: 0
    property bool isPeeking: false
    
    preventStealing: false
    propagateComposedEvents: true
    
    onPressed: (mouse) => {
        root.startY = mouse.y
        if (mouse.y > height - Theme.peekThreshold) {
            root.isPeeking = true
            peekStarted()
            mouse.accepted = true
        } else {
            mouse.accepted = false
        }
    }
    
    onPositionChanged: (mouse) => {
        if (root.isPeeking) {
            var dragY = root.startY - mouse.y
            var progress = Math.max(0, Math.min(1, 
                dragY / Theme.commitThreshold))
            peekProgress(progress)
            mouse.accepted = true
        }
    }
    
    onReleased: (mouse) => {
        if (root.isPeeking) {
            var dragY = root.startY - mouse.y
            var committed = dragY > Theme.commitThreshold
            peekReleased(committed)
            root.isPeeking = false
            mouse.accepted = true
        }
    }
}

