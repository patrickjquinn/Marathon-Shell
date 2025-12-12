import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    // No component definitions needed - we'll reference live app instances from AppLifecycleManager

    id: taskSwitcher

    // Expose HAVE_WAYLAND from C++ context
    readonly property bool haveWayland: typeof HAVE_WAYLAND !== 'undefined' ? HAVE_WAYLAND : false
    // Track pull-down progress for inline animation
    property real searchPullProgress: 0
    property bool searchGestureActive: false
    // Compositor reference for closing native apps
    property var compositor: null

    signal closed
    signal taskSelected(var task)
    signal pullDownToSearch

    scale: visible ? 1 : 0.95

    // Gesture area for pull-down to search (only when empty)
    MouseArea {
        property real startX: 0
        property real startY: 0
        property real currentY: 0
        property bool isDragging: false
        property bool isVertical: false
        readonly property real pullThreshold: 100
        readonly property real commitThreshold: 0.35

        anchors.fill: parent
        enabled: TaskModel.taskCount === 0
        z: 2
        onPressed: function (mouse) {
            startX = mouse.x;
            startY = mouse.y;
            currentY = mouse.y;
            isDragging = false;
            isVertical = false;
            taskSwitcher.searchGestureActive = false;
        }
        onPositionChanged: function (mouse) {
            if (pressed && !isDragging && !isVertical) {
                var deltaX = Math.abs(mouse.x - startX);
                var deltaY = mouse.y - startY;
                // Decide gesture direction after 10px threshold
                if (deltaX > 10 || Math.abs(deltaY) > 10) {
                    // STRICT: Vertical must be at least 3x more than horizontal (max ~18° angle)
                    if (Math.abs(deltaY) > deltaX * 3 && deltaY > 0) {
                        isVertical = true;
                        isDragging = true;
                        taskSwitcher.searchGestureActive = true;
                        Logger.info("TaskSwitcher", "Pull-down gesture started");
                    } else {
                        // Too diagonal or wrong direction - reject gesture
                        isVertical = false;
                        isDragging = false;
                        return;
                    }
                }
            }
            // Update progress in real-time during gesture
            if (isDragging && pressed) {
                currentY = mouse.y;
                var deltaY = currentY - startY;
                // Update pull progress for inline animation
                taskSwitcher.searchPullProgress = Math.min(1, deltaY / pullThreshold);
            }
        }
        onReleased: function (mouse) {
            if (isDragging && isVertical) {
                var deltaY = currentY - startY;
                var deltaTime = Date.now() - startY; // Rough approximation
                var velocity = deltaY / (deltaTime || 1);
                // If pulled down more than threshold OR fast velocity
                if (taskSwitcher.searchPullProgress > commitThreshold || velocity > 0.25) {
                    Logger.info("TaskSwitcher", "Pull down threshold met - opening search (" + deltaY + "px)");
                    UIStore.openSearch();
                    taskSwitcher.searchPullProgress = 0;
                }
            }
            isDragging = false;
            isVertical = false;
            taskSwitcher.searchGestureActive = false;
        }
        onCanceled: {
            isDragging = false;
            isVertical = false;
            taskSwitcher.searchGestureActive = false;
        }
    }

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
        propagateComposedEvents: true // Let card MouseAreas handle their events
        z: -1 // Behind the GridView
        onClicked: mouse => {
            // Only close if clicking empty space (not on a card)
            mouse.accepted = false;
            closed();
        }
    }

    Connections {
        function onTaskCountChanged() {
            Logger.info("TaskSwitcher", "TaskModel count changed: " + TaskModel.taskCount);
        }

        target: TaskModel
    }

    GridView {
        id: taskGrid

        // Allow horizontal gestures to pass through to parent PageView
        // This is critical for page switching when task switcher is full
        property bool allowHorizontalPassthrough: true

        // Velocity-aware snap to page helper function
        function snapToPage(velocity) {
            // Flick up = previous page
            // Flick down = next page
            // Slow movement = snap to nearest

            var currentPage = contentY / height;
            var targetPage;
            // Fast flick in a direction = commit to that direction
            if (velocity < -500)
                targetPage = Math.floor(currentPage);
            else if (velocity > 500)
                targetPage = Math.ceil(currentPage);
            else
                targetPage = Math.round(currentPage);
            // Clamp to valid range
            var maxPage = Math.ceil(count / 4) - 1;
            targetPage = Math.max(0, Math.min(maxPage, targetPage));
            var targetY = targetPage * height;
            snapAnimation.to = targetY;
            snapAnimation.start();
        }

        anchors.fill: parent
        anchors.margins: 16
        anchors.rightMargin: TaskModel.taskCount > 4 ? 48 : 16
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        cellWidth: width / 2
        cellHeight: height / 2
        clip: true
        Component.onCompleted: {
            console.log("[TaskSwitcher] GridView created, model count:", count);
            Logger.info("TaskSwitcher", "GridView created with " + count + " tasks");
        }
        // Only allow vertical scrolling
        flickableDirection: Flickable.VerticalFlick
        interactive: TaskModel.taskCount > 4 // Only scrollable if more than 1 page
        // Pagination settings - snap to full pages (2 rows = 4 apps)
        snapMode: GridView.NoSnap
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        boundsBehavior: Flickable.StopAtBounds
        // Smoother paging with less aggressive deceleration
        flickDeceleration: 3000
        maximumFlickVelocity: 4000
        // Velocity-aware page snapping
        onFlickEnded: snapToPage(verticalVelocity)
        onMovementEnded: {
            if (!flicking)
                snapToPage(0);
        }
        model: TaskModel
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true

        NumberAnimation {
            id: snapAnimation

            target: taskGrid
            property: "contentY"
            duration: 250
            easing.type: Easing.OutQuad // Less bouncy, snappier feel
        }

        delegate: Item {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            Component.onCompleted: {
                Logger.info("TaskSwitcher", "Delegate created for: " + model.appId + " type: " + model.type);
            }

            Rectangle {
                id: cardRoot

                property bool closing: false

                anchors.fill: parent
                anchors.margins: 8
                color: MColors.glassTitlebar
                radius: Constants.borderRadiusSharp
                border.width: Constants.borderWidthThin
                border.color: (previewTapArea.pressed || handleDragArea.pressed) ? MColors.marathonTealBright : MColors.borderSubtle
                antialiasing: Constants.enableAntialiasing
                scale: closing ? 0.7 : 1
                opacity: closing ? 0 : 1
                transform: [
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        // During drag: keep at 1.0 to avoid visual bounce from press effect toggling
                        xScale: handleDragArea.isVerticalGesture ? 1 : ((previewTapArea.pressed || handleDragArea.pressed) ? 0.98 : 1)
                        yScale: handleDragArea.isVerticalGesture ? 1 : ((previewTapArea.pressed || handleDragArea.pressed) ? 0.98 : 1)

                        Behavior on xScale {
                            // Disable during drag to prevent jitter
                            enabled: !handleDragArea.isVerticalGesture

                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on yScale {
                            // Disable during drag to prevent jitter
                            enabled: !handleDragArea.isVerticalGesture

                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    },
                    Translate {
                        // ONLY handles drag distance - no press effect here (Scale already handles it)
                        // This eliminates the discontinuity when switching from pressed to dragging
                        y: handleDragArea.dragDistance

                        Behavior on y {
                            // Disable animation during drag to follow finger precisely
                            enabled: !handleDragArea.isVerticalGesture && !handleDragArea.isDragging && !handleDragArea.pressed

                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]

                SequentialAnimation {
                    id: closeAnimation

                    ScriptAction {
                        script: cardRoot.closing = true
                    }

                    PauseAnimation {
                        duration: 250
                    }

                    ScriptAction {
                        script: {
                            Logger.info("TaskSwitcher", "Closing task: " + model.appId + " type: " + model.type + " surfaceId: " + model.surfaceId);
                            // For native apps, we need to close the Wayland surface and kill the process
                            if (model.type === "native") {
                                if (typeof compositor !== 'undefined' && compositor && model.surfaceId >= 0) {
                                    Logger.info("TaskSwitcher", "Closing native app via compositor, surfaceId: " + model.surfaceId);
                                    compositor.closeWindow(model.surfaceId);
                                }
                                // Also remove from TaskModel for native apps
                                TaskModel.closeTask(model.id);
                            } else {
                                // For Marathon apps, use lifecycle manager which handles both app closure and TaskModel removal
                                if (typeof AppLifecycleManager !== 'undefined')
                                    AppLifecycleManager.closeApp(model.appId);
                            }
                            cardRoot.closing = false;
                        }
                    }
                }

                // PREVIEW TAP AREA - Handles tap-to-open, passes all drag gestures to parent
                // This solves the gesture conflict problem by NOT handling any drag/swipe gestures
                MouseArea {
                    id: previewTapArea

                    property real startX: 0
                    property real startY: 0
                    property real startTime: 0
                    property bool wasDragging: false

                    // Cover the preview area only (not the banner)
                    anchors.fill: parent
                    anchors.bottomMargin: Math.round(50 * Constants.scaleFactor)
                    z: 50
                    preventStealing: false // CRITICAL: Allow parent GridView to steal gestures
                    onPressed: function (mouse) {
                        startX = mouse.x;
                        startY = mouse.y;
                        startTime = Date.now();
                        wasDragging = false;
                        mouse.accepted = true;
                    }
                    onPositionChanged: function (mouse) {
                        if (!pressed)
                            return;

                        var deltaX = Math.abs(mouse.x - startX);
                        var deltaY = Math.abs(mouse.y - startY);
                        // If user moves more than 8px, it's a drag - let parent handle it
                        if (deltaX > 8 || deltaY > 8) {
                            wasDragging = true;
                            mouse.accepted = false; // Release to parent
                        }
                    }
                    onReleased: function (mouse) {
                        var totalTime = Date.now() - startTime;
                        var deltaX = Math.abs(mouse.x - startX);
                        var deltaY = Math.abs(mouse.y - startY);
                        // TAP: Quick press with minimal movement
                        if (!wasDragging && totalTime < 300 && deltaX < 15 && deltaY < 15) {
                            Logger.info("TaskSwitcher", "👆 TAP on preview - Opening: " + model.appId);
                            var appId = model.appId;
                            var appTitle = model.title;
                            var appIcon = model.icon;
                            var appType = model.type;
                            Qt.callLater(function () {
                                Logger.info("TaskSwitcher", "📱 Restoring app: " + appId + " (type: " + appType + ")");
                                if (typeof AppLifecycleManager !== 'undefined') {
                                    if (appType !== "native")
                                        AppLifecycleManager.restoreApp(appId);
                                    else
                                        AppLifecycleManager.bringToForeground(appId);
                                }
                                UIStore.restoreApp(appId, appTitle, appIcon);
                                closed();
                            });
                            mouse.accepted = true;
                        } else {
                            // Was a drag or long press - let parent handle
                            mouse.accepted = false;
                        }
                        wasDragging = false;
                    }
                }

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
                                        // REMOVED: Banner overlay that was showing app title
                                        // This was always visible for native apps since they don't have liveApp instances
                                        // Native apps use Wayland surfaces (ShellSurfaceItem) instead

                                        id: previewContainer

                                        property var liveApp: null
                                        property string trackedAppId: "" // Track which app this delegate is showing
                                        // Watch model.appId directly - this detects delegate recycling
                                        property string watchedAppId: model.appId

                                        // Update liveApp reference
                                        function updateLiveApp() {
                                            Logger.debug("TaskSwitcher", "updateLiveApp called for: " + model.appId + " (type: " + model.type + ", tracked: " + trackedAppId + ")");
                                            // Clear if delegate was recycled
                                            if (trackedAppId !== "" && trackedAppId !== model.appId) {
                                                Logger.info("TaskSwitcher", "🔄 DELEGATE RECYCLED: " + trackedAppId + " → " + model.appId);
                                                liveApp = null;
                                            }
                                            trackedAppId = model.appId;
                                            // Native apps don't have MApp instances - they're managed via Wayland surfaces
                                            if (model.type === "native") {
                                                Logger.debug("TaskSwitcher", "Native app - no live preview (use surface rendering instead)");
                                                liveApp = null;
                                                return;
                                            }
                                            if (typeof AppLifecycleManager === 'undefined') {
                                                Logger.warn("TaskSwitcher", "AppLifecycleManager not available");
                                                liveApp = null;
                                                return;
                                            }
                                            var instance = AppLifecycleManager.getAppInstance(model.appId);
                                            if (!instance)
                                                Logger.debug("TaskSwitcher", "No instance yet for Marathon app: " + model.appId + " (may register soon)");
                                            else
                                                Logger.debug("TaskSwitcher", "✓ Found live app for: " + model.appId);
                                            liveApp = instance;
                                        }

                                        anchors.fill: parent
                                        visible: true // Show for all app types (Marathon and native)
                                        clip: true
                                        onWatchedAppIdChanged: {
                                            Logger.info("TaskSwitcher", "watchedAppId changed to: " + watchedAppId);
                                            updateLiveApp();
                                        }
                                        Component.onCompleted: {
                                            Logger.info("TaskSwitcher", "Preview delegate created for: " + model.appId);
                                            updateLiveApp();
                                        }

                                        // Re-check periodically in case app registers late (max 5 seconds)
                                        Timer {
                                            id: lateRegistrationTimer

                                            property int attempts: 0
                                            readonly property int maxAttempts: 50 // 5 seconds

                                            interval: 100
                                            repeat: true
                                            running: previewContainer.liveApp === null && model.type !== "native"
                                            triggeredOnStart: false
                                            onTriggered: {
                                                previewContainer.updateLiveApp();
                                                attempts++;
                                                if (attempts >= maxAttempts)
                                                    stop();
                                            }
                                            onRunningChanged: {
                                                if (running)
                                                    attempts = 0;
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
                                            // OPTIMIZATION: Disable live updates while scrolling to ensure 60fps
                                            live: previewContainer.liveApp !== null && !taskGrid.moving && !taskGrid.dragging
                                            recursive: true
                                            visible: previewContainer.liveApp !== null
                                            hideSource: false
                                            mipmap: false
                                            smooth: false
                                            format: ShaderEffectSource.RGBA
                                            samples: 0
                                            // Debug: Log when sourceItem is null (expected for inactive apps)
                                            onSourceItemChanged: {
                                                if (!sourceItem)
                                                    Logger.debug("TaskSwitcher", "NULL sourceItem for: " + model.appId + " (inactive app)");
                                                else
                                                    Logger.debug("TaskSwitcher", "✓ Preview source set for: " + model.appId);
                                            }
                                            // Force update when app becomes visible
                                            onVisibleChanged: {
                                                if (visible)
                                                    liveSnapshot.scheduleUpdate();
                                            }

                                            // Active Frames live preview throttling (10 FPS per spec)
                                            Timer {
                                                interval: 100 // 10 FPS (was 50ms/20fps) - per Marathon OS spec section 5.2
                                                repeat: true
                                                // Only run timer if live is actually enabled (double check)
                                                running: liveSnapshot.live && liveSnapshot.visible
                                                onTriggered: liveSnapshot.scheduleUpdate()
                                            }

                                            // Force update after content loads
                                            Connections {
                                                function onChildrenChanged() {
                                                    liveSnapshot.scheduleUpdate();
                                                }

                                                target: previewContainer.liveApp
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
                                            // CRITICAL: Only load when TaskSwitcher is VISIBLE
                                            active: taskSwitcher.visible && haveWayland && typeof model.waylandSurface !== 'undefined' && model.waylandSurface !== null
                                            source: haveWayland ? "qrc:/qt/qml/MarathonOS/Shell/qml/components/WaylandShellSurfaceItem.qml" : ""
                                            onItemChanged: {
                                                // surfaceObj is handled by Binding above

                                                if (item) {
                                                    // CRITICAL FIX: Anchor to the LOADER (item.parent), not "parent" (Loader's parent)
                                                    // "parent" in this scope refers to the Loader's parent (the Rectangle)
                                                    // creating a "grandchild anchors to grandparent" error.
                                                    item.anchors.fill = nativeSurfaceLoader;
                                                    item.autoResize = false;
                                                    // CRITICAL FIX: Since autoResize is false, sendSizeToApp() never runs,
                                                    // so hasSentInitialSize stays false, and opacity stays 0 (invisible).
                                                    // We must manually set it to true so the preview is visible!
                                                    item.hasSentInitialSize = true;
                                                }
                                            }

                                            // CRITICAL FIX: Use Binding to keep surface synced
                                            // This works for both initial load AND updates (reopens)
                                            Binding {
                                                target: nativeSurfaceLoader.item
                                                property: "surfaceObj"
                                                value: model.waylandSurface
                                                when: nativeSurfaceLoader.item !== null
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

                                                MAppIcon {
                                                    size: Math.round(80 * Constants.scaleFactor)
                                                    source: model.icon || "layout-grid"
                                                    anchors.horizontalCenter: parent.horizontalCenter
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

                                                MAppIcon {
                                                    size: Math.round(80 * Constants.scaleFactor)
                                                    source: model.icon || "layout-grid"
                                                    anchors.horizontalCenter: parent.horizontalCenter
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
                                    }
                                }
                            }
                        }
                    }

                    // BANNER/HANDLE AREA - Handles tap-to-open AND swipe-up-to-dismiss
                    Rectangle {
                        id: bannerRect

                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Math.round(50 * Constants.scaleFactor)
                        color: MColors.surface
                        radius: 0

                        // Handle MouseArea for swipe-to-dismiss
                        MouseArea {
                            id: handleDragArea

                            property real startX: 0
                            property real startY: 0
                            property real startTime: 0
                            property real lastY: 0
                            property real lastTime: 0
                            property real dragDistance: 0
                            property bool isDragging: false
                            property real velocity: 0
                            property bool isVerticalGesture: false
                            property bool gestureDecided: false

                            anchors.fill: parent
                            z: 100 // Above banner content but below close button
                            preventStealing: false
                            onPressed: function (mouse) {
                                // Check if click is on close button area
                                var buttonPos = closeButtonArea.mapToItem(handleDragArea, 0, 0);
                                if (mouse.x >= buttonPos.x && mouse.x <= buttonPos.x + closeButtonArea.width && mouse.y >= buttonPos.y && mouse.y <= buttonPos.y + closeButtonArea.height) {
                                    mouse.accepted = false; // Let close button handle
                                    return;
                                }
                                startX = mouse.x;
                                startY = mouse.y;
                                startTime = Date.now();
                                lastY = mouse.y;
                                lastTime = startTime;
                                dragDistance = 0;
                                isDragging = false;
                                velocity = 0;
                                isVerticalGesture = false;
                                gestureDecided = false;
                                preventStealing = false;
                                mouse.accepted = true;
                            }
                            onPositionChanged: function (mouse) {
                                if (!pressed)
                                    return;

                                var deltaX = Math.abs(mouse.x - startX);
                                var deltaY = Math.abs(mouse.y - startY);
                                var deltaYSigned = mouse.y - startY;
                                // Decide gesture after 8px movement
                                if (!gestureDecided && (deltaX > 8 || deltaY > 8)) {
                                    gestureDecided = true;
                                    if (deltaX > deltaY * 1.5) {
                                        // HORIZONTAL - pass to parent for page navigation
                                        preventStealing = false;
                                        mouse.accepted = false;
                                        Logger.info("TaskSwitcher", "🔄 Handle: Horizontal swipe → page nav");
                                        return;
                                    } else if (deltaY > deltaX * 1.5 && deltaYSigned < 0) {
                                        // VERTICAL UP - swipe to dismiss
                                        isVerticalGesture = true;
                                        preventStealing = true;
                                        Logger.info("TaskSwitcher", "↑ Handle: Vertical swipe UP → dismiss");
                                    } else {
                                        // Not a clear upward swipe, let it go
                                        mouse.accepted = false;
                                    }
                                }
                                if (isVerticalGesture) {
                                    var now = Date.now();
                                    var deltaTime = now - lastTime;
                                    var dy = mouse.y - lastY;
                                    if (deltaTime > 0)
                                        velocity = dy / deltaTime;

                                    dragDistance = deltaYSigned;
                                    lastY = mouse.y;
                                    lastTime = now;
                                    if (Math.abs(dragDistance) > 10)
                                        isDragging = true;
                                }
                            }
                            onReleased: function (mouse) {
                                var totalTime = Date.now() - startTime;
                                var deltaX = Math.abs(mouse.x - startX);
                                var deltaY = Math.abs(mouse.y - startY);
                                // SWIPE UP TO CLOSE
                                if (isVerticalGesture && isDragging) {
                                    var isFlickUp = velocity < -0.5;
                                    var isDragUp = dragDistance < -40;
                                    if (isFlickUp || isDragUp) {
                                        Logger.info("TaskSwitcher", "⬆ Handle: Closing " + model.appId);
                                        if (typeof AppLifecycleManager !== 'undefined')
                                            AppLifecycleManager.closeApp(model.appId);

                                        // Reset
                                        dragDistance = 0;
                                        isDragging = false;
                                        velocity = 0;
                                        isVerticalGesture = false;
                                        gestureDecided = false;
                                        mouse.accepted = true;
                                        return;
                                    }
                                }
                                // TAP TO OPEN
                                if (!isDragging && !isVerticalGesture && totalTime < 300 && deltaX < 15 && deltaY < 15) {
                                    Logger.info("TaskSwitcher", "👆 TAP on handle - Opening: " + model.appId);
                                    var appId = model.appId;
                                    var appTitle = model.title;
                                    var appIcon = model.icon;
                                    var appType = model.type;
                                    Qt.callLater(function () {
                                        if (typeof AppLifecycleManager !== 'undefined') {
                                            if (appType !== "native")
                                                AppLifecycleManager.restoreApp(appId);
                                            else
                                                AppLifecycleManager.bringToForeground(appId);
                                        }
                                        UIStore.restoreApp(appId, appTitle, appIcon);
                                        closed();
                                    });
                                    mouse.accepted = true;
                                    return;
                                }
                                // Reset state
                                dragDistance = 0;
                                isDragging = false;
                                velocity = 0;
                                isVerticalGesture = false;
                                gestureDecided = false;
                                preventStealing = false;
                            }
                        }

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
                                    width: Math.round(32 * Constants.scaleFactor)
                                    height: Math.round(32 * Constants.scaleFactor)
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
                                        anchors.margins: -12 // Creates 56×56 touch target
                                        z: 1000
                                        preventStealing: true
                                        onClicked: mouse => {
                                            Logger.info("TaskSwitcher", "Closing task via button: " + model.appId);
                                            mouse.accepted = true;
                                            closeAnimation.start();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Behavior on scale {
                    enabled: Constants.enableAnimations

                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on opacity {
                    enabled: Constants.enableAnimations

                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on border.color {
                    enabled: Constants.enableAnimations

                    ColorAnimation {
                        duration: Constants.animationFast
                    }
                }
            }
        }
    }

    // Vertical page indicator (shown when more than 4 apps)
    Column {
        id: pageIndicator

        property int pageCount: Math.ceil(TaskModel.taskCount / 4)
        property int currentPage: {
            // Calculate which page we're on based on contentY
            // Each page is exactly taskGrid.height tall (2 rows of cards)
            var page = Math.round(taskGrid.contentY / taskGrid.height);
            return Math.max(0, Math.min(page, pageCount - 1));
        }

        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingMedium
        visible: TaskModel.taskCount > 4
        z: 100 // Above cards

        Repeater {
            model: pageIndicator.pageCount

            Rectangle {
                width: Constants.spacingSmall / 2
                height: {
                    var isActive = index === pageIndicator.currentPage;
                    return isActive ? Constants.iconSizeMedium : Constants.pageIndicatorSizeInactive;
                }
                radius: Constants.spacingSmall / 4
                anchors.horizontalCenter: parent.horizontalCenter
                color: {
                    var isActive = index === pageIndicator.currentPage;
                    return isActive ? MColors.accent : Qt.rgba(255, 255, 255, 0.25);
                }
                border.width: 1
                border.color: {
                    var isActive = index === pageIndicator.currentPage;
                    return isActive ? Qt.rgba(20, 184, 166, 0.3) : Qt.rgba(255, 255, 255, 0.1);
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

    Behavior on opacity {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }
}
