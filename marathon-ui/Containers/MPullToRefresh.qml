import QtQuick
import MarathonUI.Theme
import MarathonUI.Effects

Item {
    id: root

    property alias contentItem: contentFlickable
    property real threshold: 80  // Distance to trigger refresh
    property bool refreshing: false
    property bool enabled: true

    signal refreshTriggered

    anchors.fill: parent

    // Pull-to-refresh indicator
    Item {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height + (contentFlickable.contentY < 0 ? Math.min(-contentFlickable.contentY, threshold) : 0)
        width: 40
        height: 40
        visible: contentFlickable.contentY < 0 || refreshing

        // Spinner
        MActivityIndicator {
            anchors.centerIn: parent
            size: 32
            running: root.refreshing
            color: MColors.marathonTeal
        }

        // Pull indicator (when not refreshing)
        Rectangle {
            visible: !root.refreshing
            anchors.centerIn: parent
            width: 32
            height: 32
            radius: 16
            color: "transparent"
            border.width: 3
            border.color: MColors.marathonTeal
            opacity: Math.min(-contentFlickable.contentY / threshold, 1.0)

            // Arrow
            Canvas {
                anchors.fill: parent
                opacity: parent.opacity

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = MColors.marathonTeal;
                    ctx.lineWidth = 3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    // Down arrow
                    ctx.beginPath();
                    ctx.moveTo(width * 0.3, height * 0.4);
                    ctx.lineTo(width * 0.5, height * 0.6);
                    ctx.lineTo(width * 0.7, height * 0.4);
                    ctx.stroke();
                }
            }
        }
    }

    // Main content area
    Flickable {
        id: contentFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.height
        boundsMovement: Flickable.StopAtBounds
        boundsBehavior: Flickable.DragAndOvershootBounds

        // Enable pull-to-refresh behavior
        onContentYChanged: {
            if (!root.enabled || root.refreshing)
                return;

            // Trigger refresh when threshold exceeded and released
            if (contentY < -threshold && !dragging && atYBeginning) {
                root.refreshing = true;
                if (MHaptics.enabled)
                    MHaptics.medium();
                root.refreshTriggered();
            }
        }

        Column {
            id: contentColumn
            width: parent.width
            // Content goes here as children
        }
    }

    // Reset refreshing state
    function stopRefreshing() {
        root.refreshing = false;
    }
}
