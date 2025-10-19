import QtQuick
import MarathonOS.Shell
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
    
    property real gestureStartX: 0
    property real gestureVelocity: 0
    property real gestureLastX: 0
    property real gestureLastTime: 0
    
    signal closed()
    signal fullyOpened()
    
    // Public API for external gesture capture
    function startPeekGesture(x) {
        root.gestureStartX = x
        root.gestureLastX = x
        root.gestureLastTime = Date.now()
        root.isPeeking = true
        Logger.info("Peek", "Gesture started from external capture")
    }
    
    function updatePeekGesture(deltaX) {
        if (!root.isPeeking) return
        
        var now = Date.now()
        var deltaTime = now - root.gestureLastTime
        
        if (deltaTime > 0) {
            root.gestureVelocity = (deltaX - (root.gestureLastX - gestureStartX)) / deltaTime * 1000
        }
        
        root.gestureLastX = gestureStartX + deltaX
        root.gestureLastTime = now
        
        // Update peek progress (0 to 1)
        root.peekProgress = Math.max(0, Math.min(1, deltaX / (peekComponent.width * 0.85)))
    }
    
    function endPeekGesture() {
        if (!root.isPeeking) return
        
        root.isPeeking = false
        
        // Velocity-based or threshold-based decision
        var shouldOpen = (root.gestureVelocity > 300) || (root.peekProgress > peekThreshold)
        
        if (shouldOpen) {
            openPeek()
        } else {
            closePeek()
        }
        
        Logger.info("Peek", "Gesture ended - " + (shouldOpen ? "opening" : "closing") + 
                    " (velocity: " + gestureVelocity.toFixed(0) + "px/s, progress: " + (root.peekProgress * 100).toFixed(0) + "%)")
    }
    
    // Main content area (dims as peek opens)
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.peekProgress * 0.6
        visible: root.peekProgress > 0
        
        MouseArea {
            anchors.fill: parent
            enabled: root.peekProgress > 0
            onClicked: {
                closePeek()
            }
        }
    }
    
    // Hub content (slides in from left)
    Item {
        id: hubPanelContainer
        width: parent.width * 0.85
        height: parent.height
        x: {
            if (root.peekProgress === 0) {
                return -width
            } else {
                return -width + (width * root.peekProgress)
            }
        }
        visible: root.peekProgress > 0 || isPeeking
        clip: true
        
        Behavior on x {
            enabled: !root.isPeeking
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
        
        MarathonHub {
            id: hubPanel
            anchors.fill: parent
            isInPeekMode: true  // Tell Hub to apply safe area padding
            
            onClosed: {
                closePeek()
            }
            
            Component.onCompleted: {
                Logger.info("Hub", "Initialized in peek panel, width: " + hubPanelContainer.width)
            }
        }
        
        // Drag-to-close gesture when peek is fully open
        // Right-side close area (avoid blocking hub tabs on left)
        MouseArea {
            id: closeGestureArea
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.3  // Right 30% of screen
            enabled: root.isFullyOpen
            z: 100  // Above hub content
            
            property real startX: 0
            property real lastX: 0
            property real velocity: 0
            property real lastTime: 0
            property bool isDragging: false
            
            onPressed: (mouse) => {
                root.startX = mouse.x
                root.lastX = mouse.x
                root.lastTime = Date.now()
                isDragging = false
                root.velocity = 0
            }
            
            onPositionChanged: (mouse) => {
                if (!isDragging) {
                    var deltaX = mouse.x - root.startX
                    // Detect left swipe (closing gesture)
                    if (deltaX < -15) {
                        isDragging = true
                        root.isPeeking = true
                        root.startX = mouse.x  // Reset for tracking
                        root.lastX = mouse.x
                        root.lastTime = Date.now()
                        Logger.info("Peek", "Close drag started")
                    }
                } else {
                    var now = Date.now()
                    var deltaTime = now - root.lastTime
                    
                    if (deltaTime > 0) {
                        root.velocity = (mouse.x - lastX) / deltaTime * 1000
                    }
                    root.lastX = mouse.x
                    root.lastTime = now
                    
                    // Update progress: deltaX from reset startX
                    var deltaX = mouse.x - root.startX
                    var maxDrag = hubPanelContainer.width
                    root.peekProgress = Math.max(0, Math.min(1, 1 + (deltaX / maxDrag)))
                }
            }
            
            onReleased: (mouse) => {
                if (isDragging) {
                    isDragging = false
                    root.isPeeking = false
                    
                    // Close if dragged left past threshold or velocity is high
                    if (root.peekProgress < 0.65 || velocity < -500) {
                        Logger.info("Peek", "Closing from drag (progress: " + root.peekProgress + ", velocity: " + velocity + ")")
                        closePeek()
                    } else {
                        // Snap back to open
                        Logger.info("Peek", "Snapping back open")
                        root.peekProgress = 1.0
                    }
                }
            }
            
            onCanceled: {
                if (isDragging) {
                    isDragging = false
                    root.isPeeking = false
                    root.peekProgress = 1.0
                }
            }
        }
    }
    
    // BackGestureIndicator removed - was visually distracting
    // The peek animation itself provides enough visual feedback
    
    // Gesture area for peek - ONLY on left edge to not block other interactions!
    MouseArea {
        id: gestureArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Constants.spacingSmall  // Narrow to not block back button
        enabled: !root.isFullyOpen
        
        property real startX: 0
        property real lastX: 0
        property real velocity: 0
        property real lastTime: 0
        
        onPressed: (mouse) => {
            // Always start peek since we're already in left edge area
            root.startX = mouse.x
            root.lastX = mouse.x
            root.lastTime = Date.now()
            root.isPeeking = true
            console.log("👈 Peek gesture started from left edge")
        }
        
        onPositionChanged: (mouse) => {
            if (!root.isPeeking) return
            
            // Calculate absolute X position (since we're in a 50px wide area)
            var absoluteX = gestureArea.x + mouse.x
            var deltaX = absoluteX - root.startX
            var now = Date.now()
            var deltaTime = now - root.lastTime
            
            if (deltaTime > 0) {
                root.velocity = (absoluteX - lastX) / deltaTime * 1000  // pixels per second
            }
            
            root.lastX = absoluteX
            root.lastTime = now
            
            // Update peek progress (0 to 1) based on parent width, not gestureArea width
            root.peekProgress = Math.max(0, Math.min(1, deltaX / (peekComponent.width * 0.85)))
        }
        
        onReleased: {
            if (!root.isPeeking) return
            
            root.isPeeking = false
            
            // Decision logic: open fully or close
            if (root.peekProgress > peekThreshold || velocity > 500) {
                // Open fully
                root.peekProgress = 1.0
                root.isFullyOpen = true
                fullyOpened()
            } else {
                // Close
                closePeek()
            }
        }
        
        onCanceled: {
            root.isPeeking = false
            closePeek()
        }
    }
    
    // Functions
    function openPeek() {
        root.peekProgress = 1.0
        root.isFullyOpen = true
        fullyOpened()
    }
    
    function closePeek() {
        root.peekProgress = 0
        root.isFullyOpen = false
        closed()
    }
    
    function openFully() {
        openPeek()
    }
    
    // Escape key to close
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && root.peekProgress > 0) {
            closePeek()
            event.accepted = true
        }
    }
    
    Component.onCompleted: {
        Logger.info("Peek", "Initialized, progress: " + root.peekProgress)
        forceActiveFocus()
    }
    
    onVisibleChanged: {
        Logger.debug("Peek", "Visibility changed: " + visible)
    }
}

