import QtQuick
import MarathonUI.Feedback
import MarathonUI.Theme
import MarathonOS.Shell
import MarathonUI.Effects

Item {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property alias contentItem: contentFlickable
    property real threshold: 80
    property bool refreshing: false

    signal refreshTriggered

    anchors.fill: parent

    Item {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height + (contentFlickable.contentY < 0 ? Math.min(-contentFlickable.contentY, root.threshold) : 0)
        width: Math.round(40 * root.scaleFactor)
        height: Math.round(40 * root.scaleFactor)
        visible: contentFlickable.contentY < 0 || root.refreshing

        MActivityIndicator {
            anchors.centerIn: parent
            size: Math.round(32 * root.scaleFactor)
            running: root.refreshing
            color: MColors.marathonTeal
        }

        Rectangle {
            visible: !root.refreshing
            anchors.centerIn: parent
            width: Math.round(32 * root.scaleFactor)
            height: Math.round(32 * root.scaleFactor)
            radius: 16
            color: "transparent"
            border.width: 3
            border.color: MColors.marathonTeal
            opacity: Math.min(-contentFlickable.contentY / root.threshold, 1.0)

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

                    ctx.beginPath();
                    ctx.moveTo(width * 0.3, height * 0.4);
                    ctx.lineTo(width * 0.5, height * 0.6);
                    ctx.lineTo(width * 0.7, height * 0.4);
                    ctx.stroke();
                }
            }
        }
    }

    Flickable {
        id: contentFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.height
        boundsMovement: Flickable.StopAtBounds
        boundsBehavior: Flickable.DragAndOvershootBounds

        onContentYChanged: {
            if (!root.enabled || root.refreshing)
                return;

            if (contentY < -root.threshold && !dragging && atYBeginning) {
                root.refreshing = true;
                if (MHaptics.enabled)
                    MHaptics.medium();
                root.refreshTriggered();
            }
        }

        Column {
            id: contentColumn
            width: parent.width
        }
    }

    function stopRefreshing() {
        root.refreshing = false;
    }
}
