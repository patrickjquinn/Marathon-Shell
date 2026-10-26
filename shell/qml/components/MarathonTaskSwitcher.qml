pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

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
                taskGrid.showPage(Math.floor(i / 4));
                return;
            }
        }
    }

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
        enabled: Tasks.taskCount === 0
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

    WallpaperTone {
        id: clockTone

        objectName: "emptyClockTone"
        x: emptyClock.x
        y: emptyClock.y - emptyClock.spacing
        width: emptyClock.width
        height: emptyClock.height + 2 * emptyClock.spacing
        visible: emptyClock.visible
    }

    // No open apps: the lock screen's clock, in the same place.
    Column {
        id: emptyClock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        // Matches MarathonLockScreen's clockColumn, compact rule included.
        anchors.topMargin: (Constants.isSquareScreen || Constants.screenHeight < 800 ? Math.round(Constants.screenHeight * 0.14) : Math.round(190 * Constants.scaleFactor)) - Constants.statusBarHeight
        width: parent.width * 0.9
        spacing: Constants.spacingSmall
        visible: Tasks.taskCount === 0
        z: 1

        Silica.Label {
            width: parent.width
            text: SystemStatusStore.timeString
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            font.pixelSize: Math.round(Silica.Theme.fontSizeHuge * 1.9)
            font.weight: Font.ExtraLight
            color: clockTone.glyph
            style: Text.Outline
            styleColor: clockTone.halo
        }
        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(taskSwitcher.today, "dddd")
            font.pixelSize: Silica.Theme.fontSizeLarge
            color: clockTone.glyph
            style: Text.Outline
            styleColor: clockTone.halo
        }
        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Day and month for the task switcher date, e.g. 26 October
            text: Qt.formatDate(taskSwitcher.today, qsTr("d MMMM"))
            font.pixelSize: Silica.Theme.fontSizeLarge
            color: clockTone.glyph
            style: Text.Outline
            styleColor: clockTone.halo
        }
    }

    Connections {
        function onTaskCountChanged() {
            Logger.info("TaskSwitcher", "Task count changed: " + Tasks.taskCount);
        }

        target: Tasks
    }

    GridView {
        id: taskGrid

        // Two by two cards a page, as BB10's active frames, filling their
        // cells whatever the screen's shape; pages scroll vertically. The
        // gap between cards and at the edges is paddingMedium.
        readonly property real gap: Silica.Theme.paddingMedium
        readonly property real bannerHeight: Silica.Theme.iconSizeSmall + 2 * Silica.Theme.paddingSmall
        readonly property int rows: Math.ceil(count / 2)
        readonly property int pages: Math.max(1, Math.ceil(rows / 2))
        readonly property real pageHeight: 2 * cellHeight
        // Every card's cover area; Keel covers are laid out at this size.
        readonly property size coverSize: Qt.size(Math.max(0, cellWidth - gap), Math.max(0, cellHeight - gap - bannerHeight))
        property int dragStartPage: 0

        function showPage(page) {
            pageAnimation.stop();
            contentY = originY + Math.max(0, Math.min(page, pages - 1)) * pageHeight;
        }

        function settle() {
            var page = dragStartPage;
            var moved = contentY - originY - dragStartPage * pageHeight;
            if (verticalVelocity > 500 || moved > pageHeight * 0.25)
                page++;
            else if (verticalVelocity < -500 || moved < -pageHeight * 0.25)
                page--;
            page = Math.max(0, Math.min(page, pages - 1));
            pageAnimation.to = originY + page * pageHeight;
            pageAnimation.restart();
        }

        anchors.fill: parent
        anchors.margins: gap / 2
        anchors.bottomMargin: Constants.bottomBarHeight + gap / 2
        cellWidth: Math.floor(width / 2)
        cellHeight: Math.floor(height / 2)
        // Pads a part-filled last page so it can be paged to.
        footer: Item {
            width: 1
            height: (taskGrid.pages * 2 - taskGrid.rows) * taskGrid.cellHeight
        }
        clip: true
        Component.onCompleted: {
            console.log("[TaskSwitcher] GridView created, model count:", count);
            Logger.info("TaskSwitcher", "GridView created with " + count + " tasks, interactive: " + interactive);
        }
        flickableDirection: Flickable.VerticalFlick
        pressDelay: 0
        interactive: pages > 1
        boundsBehavior: Flickable.StopAtBounds
        model: Tasks
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true
        onDraggingChanged: Logger.info("TaskSwitcher", "GridView dragging: " + dragging)
        onFlickingChanged: Logger.info("TaskSwitcher", "GridView flicking: " + flicking)
        onMovingChanged: Logger.info("TaskSwitcher", "GridView moving: " + moving + ", contentY: " + contentY)
        onInteractiveChanged: Logger.info("TaskSwitcher", "GridView interactive changed: " + interactive + ", taskCount: " + Tasks.taskCount)
        onDragStarted: {
            pageAnimation.stop();
            dragStartPage = Math.round((contentY - originY) / pageHeight);
        }
        onDragEnded: settle()
        onFlickStarted: cancelFlick()

        NumberAnimation {
            id: pageAnimation

            target: taskGrid
            property: "contentY"
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
        }

        delegate: TaskCard {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            bannerHeight: taskGrid.bannerHeight
            coverSize: taskGrid.coverSize
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

    Silica.FlingStopper {
        view: taskGrid
    }

    TaskPageIndicator {
        id: pageDots

        anchors.rightMargin: (taskGrid.gap - width) / 2
        gridContentY: taskGrid.contentY - taskGrid.originY
        gridContentHeight: taskGrid.pages * taskGrid.pageHeight
        gridHeight: taskGrid.pageHeight
        activeColor: dotsTone.light ? dotsTone.glyph : MColors.accent
        inactiveColor: Silica.Theme.rgba(dotsTone.glyph, 0.4)
    }

    WallpaperTone {
        id: dotsTone

        x: pageDots.x
        y: pageDots.y - pageDots.spacing
        width: pageDots.width
        height: pageDots.height + 2 * pageDots.spacing
        visible: pageDots.visible
    }

    Binding {
        target: taskSwitcher.compositor
        property: "coverSize"
        value: Qt.size(Math.floor(taskGrid.coverSize.width), Math.floor(taskGrid.coverSize.height))
        when: taskSwitcher.compositor !== null && taskGrid.coverSize.height > 0
        delayed: true
        restoreMode: Binding.RestoreNone
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Constants.animationSlow
            easing.type: Easing.OutCubic
        }
    }
}
