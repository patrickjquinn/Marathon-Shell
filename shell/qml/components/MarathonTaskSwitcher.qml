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
        // Flick up = previous page
        // Flick down = next page
        // Slow movement = snap to nearest
        // Remove custom snap animation logic
        /*
        // Velocity-aware snap to page helper function
        function snapToPage(velocity) {
             // ... removed ...
        }
        */

        id: taskGrid

        // Allow horizontal gestures to pass through to parent PageView
        // This is critical for page switching when task switcher is full
        property bool allowHorizontalPassthrough: true

        // Use SnapOneRow for page-by-page scrolling (one "page" = 2 rows = 4 cards)
        snapMode: GridView.SnapOneRow
        flickDeceleration: 1500
        maximumFlickVelocity: 3000
        anchors.fill: parent
        anchors.margins: 16
        // Right margin for the vertical page indicator
        anchors.rightMargin: TaskModel.taskCount > 4 ? 24 : 16
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        cellWidth: width / 2
        cellHeight: height / 2
        clip: true
        Component.onCompleted: {
            console.log("[TaskSwitcher] GridView created, model count:", count);
            Logger.info("TaskSwitcher", "GridView created with " + count + " tasks, interactive: " + interactive);
        }
        // Only allow vertical scrolling
        flickableDirection: Flickable.VerticalFlick
        pressDelay: 0 // Claim gestures immediately (before PageView's pressDelay: 200)
        interactive: TaskModel.taskCount > 4
        // Boundaries
        boundsBehavior: Flickable.StopAtBounds
        model: TaskModel
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true
        // DEBUG: Log gesture states
        onDraggingChanged: Logger.info("TaskSwitcher", "GridView dragging: " + dragging)
        onFlickingChanged: Logger.info("TaskSwitcher", "GridView flicking: " + flicking)
        onMovingChanged: Logger.info("TaskSwitcher", "GridView moving: " + moving + ", contentY: " + contentY)
        onInteractiveChanged: Logger.info("TaskSwitcher", "GridView interactive changed: " + interactive + ", taskCount: " + TaskModel.taskCount)

        delegate: TaskCard {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            // Context properties (not from model, need explicit binding)
            haveWayland: taskSwitcher.haveWayland
            compositor: taskSwitcher.compositor
            taskSwitcherVisible: taskSwitcher.visible
            gridMoving: taskGrid.moving
            gridDragging: taskGrid.dragging
            onClosed: taskSwitcher.closed()
        }
    }

    // Vertical page indicator (shown when more than 4 apps)
    TaskPageIndicator {
        taskCount: TaskModel.taskCount
        gridContentY: taskGrid.contentY
        gridHeight: taskGrid.height
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
