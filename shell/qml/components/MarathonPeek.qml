import QtQuick
import "../theme"
import "../stores"
import "."

// Peek & Flow - THE signature BlackBerry 10 feature
// Swipe from left edge to peek at Hub, continue to open fully
Item {
    id: peekComponent
    anchors.fill: parent
    clip: true
    
    property real peekProgress: 0  // 0 = closed, 1 = fully open
    property real peekThreshold: 0.4  // 40% of screen width triggers full open
    property bool isPeeking: false
    property bool isFullyOpen: false
    
    signal closed()
    signal fullyOpened()
    
    // Main content area (dims as peek opens)
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: peekProgress * 0.6
        visible: peekProgress > 0
        
        MouseArea {
            anchors.fill: parent
            enabled: peekProgress > 0
            onClicked: {
                closePeek()
            }
        }
    }
    
    // Hub content (slides in from left)
    MarathonHub {
        id: hubPanel
        width: parent.width * 0.85
        height: parent.height
        x: -width + (width * peekProgress)
        opacity: 0.98
        
        Behavior on x {
            enabled: !isPeeking
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
        
        onClosed: {
            closePeek()
        }
    }
    
    // Gesture area for peek - ONLY on left edge to not block other interactions!
    MouseArea {
        id: gestureArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 50  // Only 50px wide on left edge
        enabled: !isFullyOpen
        
        property real startX: 0
        property real lastX: 0
        property real velocity: 0
        property real lastTime: 0
        
        onPressed: (mouse) => {
            // Always start peek since we're already in left edge area
            startX = mouse.x
            lastX = mouse.x
            lastTime = Date.now()
            isPeeking = true
            console.log("👈 Peek gesture started from left edge")
        }
        
        onPositionChanged: (mouse) => {
            if (!isPeeking) return
            
            // Calculate absolute X position (since we're in a 50px wide area)
            var absoluteX = gestureArea.x + mouse.x
            var deltaX = absoluteX - startX
            var now = Date.now()
            var deltaTime = now - lastTime
            
            if (deltaTime > 0) {
                velocity = (absoluteX - lastX) / deltaTime * 1000  // pixels per second
            }
            
            lastX = absoluteX
            lastTime = now
            
            // Update peek progress (0 to 1) based on parent width, not gestureArea width
            peekProgress = Math.max(0, Math.min(1, deltaX / (peekComponent.width * 0.85)))
        }
        
        onReleased: {
            if (!isPeeking) return
            
            isPeeking = false
            
            // Decision logic: open fully or close
            if (peekProgress > peekThreshold || velocity > 500) {
                // Open fully
                peekProgress = 1.0
                isFullyOpen = true
                fullyOpened()
            } else {
                // Close
                closePeek()
            }
        }
        
        onCanceled: {
            isPeeking = false
            closePeek()
        }
    }
    
    // Functions
    function closePeek() {
        peekProgress = 0
        isFullyOpen = false
        closed()
    }
    
    function openFully() {
        peekProgress = 1.0
        isFullyOpen = true
        fullyOpened()
    }
    
    // Escape key to close
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && peekProgress > 0) {
            closePeek()
            event.accepted = true
        }
    }
    
    Component.onCompleted: {
        console.log("👈 Peek initialized. peekProgress:", peekProgress, "isFullyOpen:", isFullyOpen)
        forceActiveFocus()
    }
}

