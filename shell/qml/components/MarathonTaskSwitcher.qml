import QtQuick
import MarathonOS.Shell
import "."
import MarathonUI.Theme

Item {
    id: taskSwitcher
    
    // Expose HAVE_WAYLAND from C++ context
    readonly property bool haveWayland: typeof HAVE_WAYLAND !== 'undefined' ? HAVE_WAYLAND : false
    
    signal closed()
    signal taskSelected(var task)
    signal pullDownToSearch()
    
    // Track pull-down progress for inline animation
    property real searchPullProgress: 0.0
    property bool searchGestureActive: false
    
    // Compositor reference for closing native apps
    property var compositor: null
    
    // Gesture area for pull-down to search (only when empty)
    MouseArea {
        anchors.fill: parent
        enabled: TaskModel.taskCount === 0
        z: 2
        
        property real startX: 0
        property real startY: 0
        property real currentY: 0
        property bool isDragging: false
        property bool isVertical: false
        readonly property real pullThreshold: 100
        readonly property real commitThreshold: 0.35
        
        onPressed: function(mouse) {
            startX = mouse.x
            startY = mouse.y
            currentY = mouse.y
            isDragging = false
            isVertical = false
            taskSwitcher.searchGestureActive = false
        }
        
        onPositionChanged: function(mouse) {
            if (pressed && !isDragging && !isVertical) {
                var deltaX = Math.abs(mouse.x - startX)
                var deltaY = mouse.y - startY
                
                // Decide gesture direction after 10px threshold
                if (deltaX > 10 || Math.abs(deltaY) > 10) {
                    // STRICT: Vertical must be at least 3x more than horizontal (max ~18° angle)
                    if (Math.abs(deltaY) > deltaX * 3.0 && deltaY > 0) {
                        isVertical = true
                        isDragging = true
                        taskSwitcher.searchGestureActive = true
                        Logger.info("TaskSwitcher", "Pull-down gesture started")
                    } else {
                        // Too diagonal or wrong direction - reject gesture
                        isVertical = false
                        isDragging = false
                        return
                    }
                }
            }
            
            // Update progress in real-time during gesture
            if (isDragging && pressed) {
                currentY = mouse.y
                var deltaY = currentY - startY
                // Update pull progress for inline animation
                taskSwitcher.searchPullProgress = Math.min(1.0, deltaY / pullThreshold)
            }
        }
        
        onReleased: function(mouse) {
            if (isDragging && isVertical) {
                var deltaY = currentY - startY
                var deltaTime = Date.now() - startY  // Rough approximation
                var velocity = deltaY / (deltaTime || 1)
                
                // If pulled down more than threshold OR fast velocity
                if (taskSwitcher.searchPullProgress > commitThreshold || velocity > 0.25) {
                    Logger.info("TaskSwitcher", "Pull down threshold met - opening search (" + deltaY + "px)")
                    UIStore.openSearch()
                    taskSwitcher.searchPullProgress = 0.0
                }
            }
            
            isDragging = false
            isVertical = false
            taskSwitcher.searchGestureActive = false
        }
        
        onCanceled: {
            isDragging = false
            isVertical = false
            taskSwitcher.searchGestureActive = false
        }
    }
    
    // No component definitions needed - we'll reference live app instances from AppLifecycleManager
    
    // Empty state - show time and date like lock screen
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -80 - Constants.navBarHeight
        spacing: Constants.spacingSmall
        visible: TaskModel.taskCount === 0
        z: 1
        
        Text {
            text: SystemStatusStore.timeString
            color: MColors.text
            font.pixelSize: Constants.fontSizeGigantic
            font.weight: Font.Thin
            anchors.horizontalCenter: parent.horizontalCenter
            
            // Drop shadow using multiple text layers
            Text {
                text: parent.text
                color: "#80000000"
                font.pixelSize: parent.font.pixelSize
                font.weight: parent.font.weight
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2
                z: -1
            }
        }
        
        Text {
            text: SystemStatusStore.dateString
            color: MColors.text
            font.pixelSize: MTypography.sizeLarge
            font.weight: Font.Normal
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.9
            
            // Drop shadow using multiple text layers
            Text {
                text: parent.text
                color: "#80000000"
                font.pixelSize: parent.font.pixelSize
                font.weight: parent.font.weight
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2
                z: -1
                opacity: parent.opacity
            }
        }
    }
    
    // Background click to close (but don't steal events from cards)
    MouseArea {
        anchors.fill: parent
        enabled: TaskModel.taskCount > 0
        propagateComposedEvents: true  // Let card MouseAreas handle their events
        z: -1  // Behind the GridView
        onClicked: (mouse) => {
            // Only close if clicking empty space (not on a card)
            mouse.accepted = false
            closed()
        }
    }
    
    Connections {
        target: TaskModel
        function onTaskCountChanged() {
            Logger.info("TaskSwitcher", "TaskModel count changed: " + TaskModel.taskCount)
        }
    }
    
    GridView {
        id: taskGrid
        anchors.fill: parent
        anchors.margins: 16
        anchors.rightMargin: TaskModel.taskCount > 4 ? 48 : 16
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        cellWidth: width / 2
        cellHeight: height / 2
        clip: true
        
        Component.onCompleted: {
            console.log("[TaskSwitcher] GridView created, model count:", count)
            Logger.info("TaskSwitcher", "GridView created with " + count + " tasks")
        }
        
        // Only allow vertical scrolling
        flickableDirection: Flickable.VerticalFlick
        interactive: TaskModel.taskCount > 4  // Only scrollable if more than 1 page
        
        // Allow horizontal gestures to pass through to parent PageView
        // This is critical for page switching when task switcher is full
        property bool allowHorizontalPassthrough: true
        
        // Pagination settings - snap to full pages (2 rows = 4 apps)
        snapMode: GridView.NoSnap  // Disable automatic snap, use custom
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        
        // Smooth scrolling with strong snap effect
        flickDeceleration: 8000
        maximumFlickVelocity: 3000
        
        // Snap to page helper function
        function snapToPage() {
            var page = Math.round(contentY / height)
            var targetY = page * height
            snapAnimation.to = targetY
            snapAnimation.start()
        }
        
        // Custom page snapping
        onMovementEnded: snapToPage()
        onFlickEnded: snapToPage()
        
        NumberAnimation {
            id: snapAnimation
            target: taskGrid
            property: "contentY"
            duration: 200
            easing.type: Easing.OutCubic
        }
        
        model: TaskModel
        
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true
                
                delegate: Item {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    
                    Component.onCompleted: {
                        console.log("[TaskSwitcher] Delegate created for:", model.appId, "type:", model.type)
                        Logger.info("TaskSwitcher", "Delegate created for: " + model.appId + " type: " + model.type)
                    }
                    
                    Rectangle {
                        id: cardRoot
                        anchors.fill: parent
                        anchors.margins: 8
                        color: MColors.glassTitlebar
                        radius: Constants.borderRadiusSharp
                        border.width: Constants.borderWidthThin
                        border.color: cardDragArea.pressed ? MColors.marathonTealBright : MColors.borderSubtle
                        antialiasing: Constants.enableAntialiasing
                        
                        property bool closing: false
                        
                        scale: closing ? 0.7 : 1.0
                        opacity: closing ? 0.0 : 1.0
                        
                        Behavior on scale {
                            enabled: Constants.enableAnimations
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        
                        Behavior on opacity {
                            enabled: Constants.enableAnimations
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        
                        Behavior on border.color {
                            enabled: Constants.enableAnimations
                            ColorAnimation { duration: Constants.animationFast }
                        }
                        
                        SequentialAnimation {
                            id: closeAnimation
                            
                            ScriptAction {
                                script: cardRoot.closing = true
                            }
                            
                            PauseAnimation { duration: 250 }
                            
                            ScriptAction {
                                script: {
                                    Logger.info("TaskSwitcher", "Closing task: " + model.appId + " type: " + model.type + " surfaceId: " + model.surfaceId)
                                    
                                    // For native apps, we need to close the Wayland surface and kill the process
                                    if (model.type === "native") {
                                        if (typeof compositor !== 'undefined' && compositor && model.surfaceId >= 0) {
                                            Logger.info("TaskSwitcher", "Closing native app via compositor, surfaceId: " + model.surfaceId)
                                            compositor.closeWindow(model.surfaceId)
                                        }
                                        // Also remove from TaskModel for native apps
                                        TaskModel.closeTask(model.id)
                                    } else {
                                        // For Marathon apps, use lifecycle manager which handles both app closure and TaskModel removal
                                        if (typeof AppLifecycleManager !== 'undefined') {
                                            AppLifecycleManager.closeApp(model.appId)
                                        }
                                    }
                                    
                                    cardRoot.closing = false
                                }
                            }
                        }
                
                // FULL CARD MouseArea for dragging (covers preview AND banner)
                MouseArea {
                    id: cardDragArea
                    anchors.fill: parent
                    z: 50  // Below close button (z: 1000) but above content
                    preventStealing: false  // Allow gesture direction detection
                    
                    property real startX: 0
                    property real startY: 0
                    property real startTime: 0
                    property real lastY: 0
                    property real lastTime: 0
                    property real dragDistance: 0
                    property bool isDragging: false
                    property real velocity: 0
                    property bool closeButtonClicked: false
                    property bool isVerticalGesture: false
                    property bool isHorizontalGesture: false
                    property bool gestureDecided: false
                    
                    onPressed: function(mouse) {
                        Logger.info("TaskSwitcher", "⬇ PRESSED card: " + model.appId + " at (" + mouse.x + ", " + mouse.y + ")")
                        
                        // Check if click is on close button - let it handle
                        var buttonPos = closeButtonArea.mapToItem(cardDragArea, 0, 0)
                        var isOnButton = mouse.x >= buttonPos.x && 
                                        mouse.x <= buttonPos.x + closeButtonArea.width &&
                                        mouse.y >= buttonPos.y && 
                                        mouse.y <= buttonPos.y + closeButtonArea.height
                        
                        if (isOnButton) {
                            Logger.debug("TaskSwitcher", "Click on close button detected, passing through")
                            closeButtonClicked = true
                            mouse.accepted = false  // Let close button handle
                            return
                        }
                        
                        startX = mouse.x
                        startY = mouse.y
                        startTime = Date.now()
                        lastY = mouse.y
                        lastTime = startTime
                        dragDistance = 0
                        isDragging = false
                        velocity = 0
                        closeButtonClicked = false
                        isVerticalGesture = false
                        isHorizontalGesture = false
                        gestureDecided = false
                        preventStealing = false  // Reset to allow parent to steal if needed
                        mouse.accepted = true  // Initially accept
                    }
                    
                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        
                        var deltaX = Math.abs(mouse.x - startX)
                        var deltaY = Math.abs(mouse.y - startY)
                        var deltaYSigned = mouse.y - startY
                        
                        // CRITICAL: Early gesture detection (after just 8px movement)
                        if (!gestureDecided && (deltaX > 8 || deltaY > 8)) {
                            gestureDecided = true
                            
                            // Determine gesture type:
                            // - Horizontal: deltaX > deltaY * 1.5 (horizontal dominates)
                            // - Vertical: deltaY > deltaX * 1.5 (vertical dominates)
                            // - Ambiguous: Will be treated as tap if released quickly
                            
                            if (deltaX > deltaY * 1.5) {
                                // HORIZONTAL gesture - pass to parent for page switching
                                isHorizontalGesture = true
                                isVerticalGesture = false
                                preventStealing = false
                                mouse.accepted = false  // Pass to parent immediately
                                Logger.info("TaskSwitcher", "🔄 Horizontal swipe detected - passing to parent for page navigation")
                                return
                            } else if (deltaY > deltaX * 1.5) {
                                // VERTICAL gesture - handle for card dismissal
                                isVerticalGesture = true
                                isHorizontalGesture = false
                                preventStealing = true  // Prevent parent from stealing
                                Logger.info("TaskSwitcher", "↕ Vertical swipe detected - handling for card dismissal")
                            } else {
                                // Ambiguous - don't claim yet, treat as potential tap
                                Logger.debug("TaskSwitcher", "❓ Ambiguous gesture - will treat as tap if quick")
                            }
                        }
                        
                        // Only track vertical movement if it's a vertical gesture
                        if (isVerticalGesture) {
                            var now = Date.now()
                            var deltaTime = now - lastTime
                            var dy = mouse.y - lastY
                            
                            // Calculate instantaneous velocity
                            if (deltaTime > 0) {
                                velocity = dy / deltaTime
                            }
                            
                            dragDistance = deltaYSigned
                            lastY = mouse.y
                            lastTime = now
                            
                            // Start dragging after 10px movement
                            if (Math.abs(dragDistance) > 10) {
                                isDragging = true
                            }
                        }
                    }
                    
                    onReleased: function(mouse) {
                        Logger.info("TaskSwitcher", "⬆ RELEASED card: " + model.appId + 
                            " (time: " + (Date.now() - startTime) + "ms, " +
                            "dragging: " + isDragging + ", " +
                            "vertical: " + isVerticalGesture + ", " +
                            "horizontal: " + isHorizontalGesture + ")")
                        
                        // If close button was clicked, ignore
                        if (closeButtonClicked) {
                            Logger.debug("TaskSwitcher", "Close button clicked, ignoring")
                            closeButtonClicked = false
                            return
                        }
                        
                        // If it was a horizontal gesture, we already passed it to parent
                        if (isHorizontalGesture) {
                            Logger.debug("TaskSwitcher", "Horizontal gesture handled by parent")
                            // Reset state
                            isDragging = false
                            gestureDecided = false
                            dragDistance = 0
                            isHorizontalGesture = false
                            isVerticalGesture = false
                            preventStealing = false
                            return
                        }
                        
                        var totalTime = Date.now() - startTime
                        Logger.info("TaskSwitcher", "Gesture analysis: totalTime=" + totalTime + "ms, isDragging=" + isDragging + ", gestureDecided=" + gestureDecided)
                        
                        // VERTICAL DRAG: Check for flick/drag up to close
                        if (isVerticalGesture && isDragging) {
                            // Use instantaneous velocity (more responsive to flicks)
                            // Flick up: velocity < -0.5 px/ms (more lenient)
                            // OR drag up > 50px (reduced from 80px)
                            var isFlickUp = velocity < -0.5
                            var isDragUp = dragDistance < -50
                            
                            if (isFlickUp || isDragUp) {
                                Logger.info("TaskSwitcher", " Closing card: " + model.appId + " (velocity: " + velocity.toFixed(2) + "px/ms, distance: " + dragDistance.toFixed(0) + "px)")
                                
                                var appIdToClose = model.appId
                                
                                // Reset transform immediately to avoid ghost spacing
                                dragDistance = 0
                                isDragging = false
                                velocity = 0
                                isVerticalGesture = false
                                gestureDecided = false
                                preventStealing = false
                                
                                // Close the app - AppLifecycleManager will handle both the app instance AND removing from TaskModel
                                if (typeof AppLifecycleManager !== 'undefined') {
                                    AppLifecycleManager.closeApp(appIdToClose)
                                }
                                
                                mouse.accepted = true
                            } else {
                                // Vertical drag but didn't reach threshold - just reset
                                Logger.debug("TaskSwitcher", "Vertical drag didn't reach threshold, resetting")
                                dragDistance = 0
                                isDragging = false
                                velocity = 0
                                isVerticalGesture = false
                                gestureDecided = false
                                preventStealing = false
                            }
                        } else if (!isDragging && !isVerticalGesture && !isHorizontalGesture && totalTime < 250) {
                            // TAP DETECTED - Quick press/release with minimal movement
                            Logger.info("TaskSwitcher", " TAP DETECTED - Opening task: " + model.appId)
                            var appId = model.appId
                            var appTitle = model.title
                            var appIcon = model.icon
                            var appType = model.type
                            
                            // Reset state immediately
                            dragDistance = 0
                            isDragging = false
                            velocity = 0
                            isVerticalGesture = false
                            isHorizontalGesture = false
                            gestureDecided = false
                            preventStealing = false
                            
                            // Defer restoration to avoid blocking UI
                            Qt.callLater(function() {
                                Logger.info("TaskSwitcher", "📱 Restoring app: " + appId + " (type: " + appType + ")")
                                
                                // For Marathon apps, restore through lifecycle manager
                                // For native apps, AppLifecycleManager handles foreground state
                                if (typeof AppLifecycleManager !== 'undefined') {
                                    if (appType !== "native") {
                                        AppLifecycleManager.restoreApp(appId)
                                    } else {
                                        // Native apps need foreground tracking too
                                        AppLifecycleManager.bringToForeground(appId)
                                    }
                                }
                                
                                // Then update UI state (this triggers the restoration in MarathonShell.qml)
                                Logger.info("TaskSwitcher", "📢 Calling UIStore.restoreApp(" + appId + ")")
                                UIStore.restoreApp(appId, appTitle, appIcon)
                                Logger.info("TaskSwitcher", "🚪 Closing task switcher")
                                closed()
                            })
                            mouse.accepted = true
                        } else {
                            // Some other gesture or long press - reset
                            Logger.debug("TaskSwitcher", "Unhandled gesture, resetting (time: " + totalTime + "ms)")
                            dragDistance = 0
                            isDragging = false
                            velocity = 0
                            isVerticalGesture = false
                            isHorizontalGesture = false
                            gestureDecided = false
                            preventStealing = false
                            mouse.accepted = false
                        }
                    }
                }
                
                transform: [
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: cardDragArea.pressed ? 0.98 : 1.0
                        yScale: cardDragArea.pressed ? 0.98 : 1.0
                        
                        Behavior on xScale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on yScale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    },
                    Translate {
                        y: cardDragArea.isDragging ? cardDragArea.dragDistance : 
                           (cardDragArea.closeButtonClicked ? 0 : 
                            (cardDragArea.pressed ? -2 : 0))
                        
                        Behavior on y {
                            enabled: !cardDragArea.isDragging
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]
                
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.03)
                }
                        
                        Item {
                            anchors.fill: parent
                            
                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: Math.round(50 * Constants.scaleFactor)
                                color: MColors.background
                                radius: parent.parent.radius
                                
                                Loader {
                                    id: appPreview
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    active: true
            asynchronous: true
                                    
                                    sourceComponent: Item {
                                        anchors.fill: parent
                                        clip: true
                                        
                                        Item {
                                            id: livePreview
                                            anchors.fill: parent
                                            
                                            Item {
                                                id: previewContainer
                                                anchors.fill: parent
                                                visible: true  // Show for all app types (Marathon and native)
                                                clip: true
                                                
                                                property var liveApp: null
                                                property string trackedAppId: ""  // Track which app this delegate is showing
                                                
                                                // Update liveApp reference
                                                function updateLiveApp() {
                                                    Logger.debug("TaskSwitcher", "updateLiveApp called for: " + model.appId + " (type: " + model.type + ", tracked: " + trackedAppId + ")")
                                                    
                                                    // Clear if delegate was recycled
                                                    if (trackedAppId !== "" && trackedAppId !== model.appId) {
                                                        Logger.info("TaskSwitcher", "🔄 DELEGATE RECYCLED: " + trackedAppId + " → " + model.appId)
                                                        liveApp = null
                                                    }
                                                    
                                                    trackedAppId = model.appId
                                                    
                                                    // Native apps don't have MApp instances - they're managed via Wayland surfaces
                                                    if (model.type === "native") {
                                                        Logger.debug("TaskSwitcher", "Native app - no live preview (use surface rendering instead)")
                                                        liveApp = null
                                                        return
                                                    }
                                                    
                                                    if (typeof AppLifecycleManager === 'undefined') {
                                                        Logger.warn("TaskSwitcher", "AppLifecycleManager not available")
                                                        liveApp = null
                                                        return
                                                    }
                                                    
                                                    var instance = AppLifecycleManager.getAppInstance(model.appId)
                                                    if (!instance) {
                                                        Logger.debug("TaskSwitcher", "No instance yet for Marathon app: " + model.appId + " (may register soon)")
                                                    } else {
                                                        Logger.debug("TaskSwitcher", "✓ Found live app for: " + model.appId)
                                                    }
                                                    liveApp = instance
                                                }
                                                
                                                // Watch model.appId directly - this detects delegate recycling
                                                property string watchedAppId: model.appId
                                                onWatchedAppIdChanged: {
                                                    Logger.info("TaskSwitcher", "watchedAppId changed to: " + watchedAppId)
                                                    updateLiveApp()
                                                }
                                                
                                                Component.onCompleted: {
                                                    Logger.info("TaskSwitcher", "Preview delegate created for: " + model.appId)
                                                    updateLiveApp()
                                                }
                                                
                                                // Re-check periodically in case app registers late (max 5 seconds)
                                                Timer {
                                                    id: lateRegistrationTimer
                                                    interval: 100
                                                    repeat: true
                                                    running: previewContainer.liveApp === null && model.type !== "native"
                                                    triggeredOnStart: false
                                                    property int attempts: 0
                                                    readonly property int maxAttempts: 50 // 5 seconds
                                                    onTriggered: {
                                                        previewContainer.updateLiveApp()
                                                        attempts++
                                                        if (attempts >= maxAttempts) {
                                                            stop()
                                                        }
                                                    }
                                                    onRunningChanged: {
                                                        if (running) attempts = 0
                                                    }
                                                }
                                                
                                                // Live preview using ShaderEffectSource with forced updates
                                                ShaderEffectSource {
                                                    id: liveSnapshot
                                                    anchors.top: parent.top
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: parent.width
                                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                                    sourceItem: previewContainer.liveApp
                                                    live: true
                                                    recursive: true
                                                    visible: previewContainer.liveApp !== null
                                                    hideSource: false
                                                    mipmap: false
                                                    smooth: false
                                                    format: ShaderEffectSource.RGBA
                                                    samples: 0
                                                    
                                                    // Debug: Log when sourceItem is null (expected for inactive apps)
                                                    onSourceItemChanged: {
                                                        if (!sourceItem) {
                                                            Logger.debug("TaskSwitcher", "NULL sourceItem for: " + model.appId + " (inactive app)")
                                                        } else {
                                                            Logger.debug("TaskSwitcher", "✓ Preview source set for: " + model.appId)
                                                        }
                                                    }
                                                    
                                                // Active Frames live preview throttling (10 FPS per spec)
                                                Timer {
                                                    interval: 100  // 10 FPS (was 50ms/20fps) - per Marathon OS spec section 5.2
                                                    repeat: true
                                                    running: liveSnapshot.visible && !taskGrid.moving && !taskGrid.dragging
                                                    onTriggered: liveSnapshot.scheduleUpdate()
                                                }
                                                    
                                                    // Force update after content loads
                                                    Connections {
                                                        target: previewContainer.liveApp
                                                        function onChildrenChanged() {
                                                            liveSnapshot.scheduleUpdate()
                                                        }
                                                    }
                                                    
                                                    // Force update when app becomes visible
                                                    onVisibleChanged: {
                                                        if (visible) {
                                                            liveSnapshot.scheduleUpdate()
                                                        }
                                                    }
                                                }
                                                
                                                // Native app surface rendering - conditionally load Wayland component on Linux
                                                Loader {
                                                    id: nativeSurfaceLoader
                                                    anchors.top: parent.top
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: parent.width
                                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                                    visible: model.type === "native"
                                                    active: haveWayland && typeof model.waylandSurface !== 'undefined' && model.waylandSurface !== null
                                                    source: haveWayland ? "qrc:/MarathonOS/Shell/qml/components/WaylandShellSurfaceItem.qml" : ""
                                                    
                                                    property var surfaceObj: typeof model.waylandSurface !== 'undefined' ? model.waylandSurface : null
                                                    
                                                    onItemChanged: {
                                                        if (item && surfaceObj) {
                                                            item.surfaceObj = surfaceObj
                                                        }
                                                    }
                                                }
                                                
                                                // Fallback for native apps when Wayland is not available (macOS)
                                                        Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: parent.width
                                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                                    visible: model.type === "native" && !haveWayland
                                                            color: MColors.elevated
                                                            
                                                    Column {
                                                                anchors.centerIn: parent
                                                        spacing: Constants.spacingMedium
                                                        
                                                        Image {
                                                            width: Math.round(80 * Constants.scaleFactor)
                                                            height: Math.round(80 * Constants.scaleFactor)
                                                            source: model.icon || "qrc:/images/icons/lucide/grid.svg"
                                                            sourceSize.width: Math.round(80 * Constants.scaleFactor)
                                                            sourceSize.height: 80
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            smooth: true
                                                            fillMode: Image.PreserveAspectFit
                                                        }
                                                        
                                                        Text {
                                                            text: model.title || model.appId
                                                                color: MColors.textSecondary
                                                                font.pixelSize: MTypography.sizeSmall
                                                            font.family: MTypography.fontFamily
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                        }
                                                        
                                                        Text {
                                                            text: "Native apps not available on macOS"
                                                            color: MColors.textTertiary
                                                            font.pixelSize: MTypography.sizeXSmall
                                                            font.family: MTypography.fontFamily
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                        }
                                                    }
                                                }
                                                
                                                // Fallback: Show app icon when live preview unavailable
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: parent.width
                                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                                    visible: previewContainer.liveApp === null && (model.type !== "native" || !model.waylandSurface)
                                                    color: MColors.background
                                                    
                                                    Column {
                                                        anchors.centerIn: parent
                                                        spacing: Constants.spacingMedium
                                                        
                                                        Image {
                                                            width: Math.round(80 * Constants.scaleFactor)
                                                            height: Math.round(80 * Constants.scaleFactor)
                                                            source: model.icon || "qrc:/images/icons/lucide/grid.svg"
                                                            sourceSize.width: Math.round(80 * Constants.scaleFactor)
                                                            sourceSize.height: 80
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            smooth: true
                                                            fillMode: Image.PreserveAspectFit
                                                        }
                                                        
                                                        Text {
                                                            text: model.title || model.appId
                                                            color: MColors.textSecondary
                                                            font.pixelSize: MTypography.sizeSmall
                                                            font.family: MTypography.fontFamily
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                        }
                                                        
                                                        Text {
                                                            text: "Preview unavailable"
                                                            color: MColors.textTertiary
                                                            font.pixelSize: MTypography.sizeXSmall
                                                            font.family: MTypography.fontFamily
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                        }
                                                    }
                                                }
                                                

                                                
                                                // REMOVED: Banner overlay that was showing app title
                                                // This was always visible for native apps since they don't have liveApp instances
                                                // Native apps use Wayland surfaces (ShellSurfaceItem) instead
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Math.round(50 * Constants.scaleFactor)
                        color: MColors.surface
                                radius: 0
                                
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Constants.spacingSmall
                                    anchors.rightMargin: Constants.spacingSmall
                                    spacing: Constants.spacingSmall
                                    
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                source: model.icon
                                        width: Constants.iconSizeMedium
                                        height: Constants.iconSizeMedium
                                        fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
                                        smooth: true
                                sourceSize: Qt.size(32, 32)
                                    }
                                    
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Math.round(80 * Constants.scaleFactor)
                                        spacing: Math.round(2 * Constants.scaleFactor)
                                        
                                        Text {
                                    text: model.title
                                                            color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: Font.DemiBold
                                            font.family: MTypography.fontFamily
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                        
                                        Text {
                                    text: model.subtitle || "Running"
                                                            color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeXSmall
                                            font.family: MTypography.fontFamily
                                    opacity: 0.7
                                        }
                                    }
                                    
                                    Item {
                                        id: closeButtonContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Constants.iconSizeMedium
                                        height: Constants.iconSizeMedium
                                        
                                        Rectangle {
                                            id: closeButtonRect
                                            anchors.centerIn: parent
                                            width: Math.round(28 * Constants.scaleFactor)
                                            height: Math.round(28 * Constants.scaleFactor)
                                    radius: MRadius.sm
                                    color: MColors.surface
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "×"
                                                            color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeLarge
                                                font.weight: Font.Bold
                                            }
                                            
                                            MouseArea {
                                                id: closeButtonArea
                                                anchors.fill: parent
                                                anchors.margins: -8
                                                z: 1000
                                                preventStealing: true
                                                
                                                onPressed: (mouse) => {
                                                    cardDragArea.closeButtonClicked = true
                                                    mouse.accepted = true  // Block card drag area
                                                }
                                                
                                                onReleased: (mouse) => {
                                                    mouse.accepted = true  // Consume release
                                                }
                                                
                                            onClicked: (mouse) => {
                                                Logger.info("TaskSwitcher", "Closing task via button: " + model.appId)
                                                mouse.accepted = true  // Consume click
                                                
                                                closeAnimation.start()
                                                
                                                cardDragArea.closeButtonClicked = false
                                            }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
            }
        }
    }
    
    Behavior on opacity {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }
    
    scale: visible ? 1.0 : 0.95
    Behavior on scale {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }
    
    // Vertical page indicator (shown when more than 4 apps)
    Column {
        id: pageIndicator
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingMedium
        visible: TaskModel.taskCount > 4
        z: 100  // Above cards
        
        property int pageCount: Math.ceil(TaskModel.taskCount / 4)
        property int currentPage: {
            // Calculate which page we're on based on contentY
            // Each page is exactly taskGrid.height tall (2 rows of cards)
            var page = Math.round(taskGrid.contentY / taskGrid.height)
            return Math.max(0, Math.min(page, pageCount - 1))
        }
        
        Repeater {
            model: pageIndicator.pageCount
            
            Rectangle {
                width: Constants.spacingSmall / 2
                height: {
                    var isActive = index === pageIndicator.currentPage
                    return isActive ? Constants.iconSizeMedium : Constants.pageIndicatorSizeInactive
                }
                radius: Constants.spacingSmall / 4
                anchors.horizontalCenter: parent.horizontalCenter
                
                color: {
                    var isActive = index === pageIndicator.currentPage
                    return isActive ? MColors.accent : Qt.rgba(255, 255, 255, 0.25)
                }
                
                border.width: 1
                border.color: {
                    var isActive = index === pageIndicator.currentPage
                    return isActive ? Qt.rgba(20, 184, 166, 0.3) : Qt.rgba(255, 255, 255, 0.1)
                }
                
                layer.enabled: true
                
                Behavior on height {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
                
                Behavior on color {
                    ColorAnimation {
                        duration: 250
                    }
                }
                
                Behavior on border.color {
                    ColorAnimation {
                        duration: 250
                    }
                }
            }
        }
    }
}
