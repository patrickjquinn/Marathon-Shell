import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: taskSwitcher

    readonly property bool haveWayland: typeof HAVE_WAYLAND !== 'undefined' ? HAVE_WAYLAND : false
    property real searchPullProgress: 0
    property bool searchGestureActive: false
    property var compositor: null

    signal closed
    signal taskSelected(var task)
    signal pullDownToSearch

    scale: visible ? 1 : 0.95

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
                if (deltaX > 10 || Math.abs(deltaY) > 10) {
                    if (Math.abs(deltaY) > deltaX * 3 && deltaY > 0) {
                        isVertical = true;
                        isDragging = true;
                        taskSwitcher.searchGestureActive = true;
                        Logger.info("TaskSwitcher", "Pull-down gesture started");
                    } else {
                        isVertical = false;
                        isDragging = false;
                        return;
                    }
                }
            }
            if (isDragging && pressed) {
                currentY = mouse.y;
                var deltaY = currentY - startY;
                taskSwitcher.searchPullProgress = Math.min(1, deltaY / pullThreshold);
            }
        }
        onReleased: function (mouse) {
            if (isDragging && isVertical) {
                var deltaY = currentY - startY;
                var deltaTime = Date.now() - startY;
                var velocity = deltaY / (deltaTime || 1);
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

    MouseArea {
        anchors.fill: parent
        enabled: TaskModel.taskCount > 0
        propagateComposedEvents: true
        z: -1
        onClicked: mouse => {
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

        property bool allowHorizontalPassthrough: true

        snapMode: GridView.SnapOneRow
        flickDeceleration: 1500
        maximumFlickVelocity: 3000
        anchors.fill: parent
        anchors.margins: 16
        anchors.rightMargin: TaskModel.taskCount > 4 ? 24 : 16
        anchors.bottomMargin: Constants.bottomBarHeight + 16
        cellWidth: width / 2
        cellHeight: height / 2
        clip: true
        Component.onCompleted: {
            console.log("[TaskSwitcher] GridView created, model count:", count);
            Logger.info("TaskSwitcher", "GridView created with " + count + " tasks, interactive: " + interactive);
        }
        flickableDirection: Flickable.VerticalFlick
        pressDelay: 0
        interactive: TaskModel.taskCount > 4
        boundsBehavior: Flickable.StopAtBounds
        model: TaskModel
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true
        onDraggingChanged: Logger.info("TaskSwitcher", "GridView dragging: " + dragging)
        onFlickingChanged: Logger.info("TaskSwitcher", "GridView flicking: " + flicking)
        onMovingChanged: Logger.info("TaskSwitcher", "GridView moving: " + moving + ", contentY: " + contentY)
        onInteractiveChanged: Logger.info("TaskSwitcher", "GridView interactive changed: " + interactive + ", taskCount: " + TaskModel.taskCount)

        delegate: TaskCard {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            haveWayland: taskSwitcher.haveWayland
            compositor: taskSwitcher.compositor
            taskSwitcherVisible: taskSwitcher.visible
            gridMoving: taskGrid.moving
            gridDragging: taskGrid.dragging
            onClosed: taskSwitcher.closed()
        }
    }

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
