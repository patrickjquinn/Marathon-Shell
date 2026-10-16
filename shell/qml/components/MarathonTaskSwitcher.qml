pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: taskSwitcher

    readonly property bool haveWayland: HAVE_WAYLAND
    // TaskCard's cover corners.
    readonly property real coverRadius: Silica.Theme.paddingMedium
    // Whether this page is the one on screen. `visible` cannot answer that:
    // a MarathonPageView delegate is translated off screen rather than
    // hidden, so it stays true from creation to destruction. Defaults true
    // for a caller that shows the switcher on its own.
    property bool pageActive: true
    property real searchPullProgress: 0
    property bool searchGestureActive: false
    property var compositor: null
    // Re-read when the date string turns over at midnight.
    readonly property date today: SystemStatusStore.dateString ? new Date() : new Date()

    signal closed

    // Scene rect of an app's cover in the grid; empty when it has no card.
    function cardRect(appId) {
        for (var i = 0; i < taskGrid.count; ++i) {
            var card = taskGrid.itemAtIndex(i) as TaskCard;
            if (card && card.appId === appId)
                return card.coverSceneRect();
        }
        return Qt.rect(0, 0, 0, 0);
    }

    function revealCard(appId) {
        for (var i = 0; i < taskGrid.count; ++i) {
            var card = taskGrid.itemAtIndex(i) as TaskCard;
            if (card && card.appId === appId) {
                taskGrid.positionViewAtIndex(i, GridView.Contain);
                return;
            }
        }
    }

    scale: visible ? 1 : 0.95
    Component.onCompleted: WindowOrigins.switcher = taskSwitcher
    Component.onDestruction: {
        if (WindowOrigins.switcher === taskSwitcher)
            WindowOrigins.switcher = null;
    }

    MouseArea {
        property real startX: 0
        property real startY: 0
        property real startTime: 0
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
            startTime = Date.now();
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
                var deltaTime = Date.now() - startTime;
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

    // No open apps: the lock screen's clock, in the same place.
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        // Matches MarathonLockScreen's clockColumn, compact rule included.
        anchors.topMargin: (Constants.isSquareScreen || Constants.screenHeight < 800 ? Math.round(Constants.screenHeight * 0.14) : Math.round(190 * Constants.scaleFactor)) - Constants.statusBarHeight
        width: parent.width * 0.9
        spacing: Constants.spacingSmall
        visible: TaskModel.taskCount === 0
        z: 1

        Silica.Label {
            width: parent.width
            text: SystemStatusStore.timeString
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            font.pixelSize: Math.round(Silica.Theme.fontSizeHuge * 1.9)
            font.weight: Font.ExtraLight
            color: Silica.Theme.primaryColor
        }
        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(taskSwitcher.today, "dddd")
            font.pixelSize: Silica.Theme.fontSizeLarge
            color: Silica.Theme.primaryColor
        }
        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(taskSwitcher.today, "d MMMM")
            font.pixelSize: Silica.Theme.fontSizeLarge
            color: Silica.Theme.primaryColor
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: TaskModel.taskCount > 0
        propagateComposedEvents: true
        z: -1
        onClicked: mouse => {
            mouse.accepted = false;
            taskSwitcher.closed();
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

        snapMode: GridView.SnapOneRow
        flickDeceleration: 1500
        maximumFlickVelocity: 3000
        anchors.fill: parent
        anchors.margins: Silica.Theme.paddingLarge
        // Cards keep the cover's proportions: two columns where two rows of
        // them fit (tall phones), otherwise three, a row to a page (square
        // screens). Rows are spread over the page so none is cut off.
        readonly property bool overflows: contentHeight > height
        readonly property real coverAspect: Silica.Theme.coverSizeLarge.height / Silica.Theme.coverSizeLarge.width
        readonly property real bannerHeight: Silica.Theme.iconSizeSmall + 2 * Silica.Theme.paddingSmall
        readonly property real cardChrome: bannerHeight + 2 * Silica.Theme.paddingSmall
        readonly property int columns: 2 * ((width / 2 - 2 * Silica.Theme.paddingSmall) * coverAspect + cardChrome) <= height ? 2 : 3
        readonly property real cardHeight: Math.min(height, (cellWidth - 2 * Silica.Theme.paddingSmall) * coverAspect + cardChrome)
        readonly property int rowsPerPage: Math.max(1, Math.floor(height / cardHeight))

        anchors.rightMargin: overflows ? Silica.Theme.paddingLarge + Silica.Theme.paddingSmall : Silica.Theme.paddingLarge
        anchors.bottomMargin: Constants.bottomBarHeight + Silica.Theme.paddingLarge
        cellWidth: width / columns
        cellHeight: height / rowsPerPage
        clip: true
        Component.onCompleted: {
            console.log("[TaskSwitcher] GridView created, model count:", count);
            Logger.info("TaskSwitcher", "GridView created with " + count + " tasks, interactive: " + interactive);
        }
        flickableDirection: Flickable.VerticalFlick
        pressDelay: 0
        interactive: overflows
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
            bannerHeight: taskGrid.bannerHeight
            haveWayland: taskSwitcher.haveWayland
            compositor: taskSwitcher.compositor
            taskSwitcherVisible: taskSwitcher.visible && taskSwitcher.pageActive
            gridMoving: taskGrid.moving
            gridDragging: taskGrid.dragging
            swipeClaimsDrag: !taskGrid.interactive || taskGrid.atYEnd
            onClosed: taskSwitcher.closed()
        }

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: MMotion.durationFor("entrance")
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "scale"
                from: 0.9
                to: 1
                duration: MMotion.durationFor("entrance")
                easing.type: Easing.OutCubic
            }
        }

        remove: Transition {
            NumberAnimation {
                property: "opacity"
                to: 0
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "scale"
                to: 0.9
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }

        // Neighbours close the gap; an interrupted add still ends opaque.
        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                properties: "opacity,scale"
                to: 1
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
        }
    }

    TaskPageIndicator {
        gridContentY: taskGrid.contentY
        gridContentHeight: taskGrid.contentHeight
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
