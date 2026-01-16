import QtQuick
import QtQuick.Controls

Flickable {
    id: root

    default property alias content: contentContainer.data

    contentHeight: contentContainer.height
    clip: true

    flickDeceleration: 5000
    maximumFlickVelocity: 2500
    boundsBehavior: Flickable.DragAndOvershootBounds

    readonly property bool isScrollable: true
    function scrollBy(pixels) {
        flick(0, pixels * 5);
    }

    WheelHandler {
        onWheel: event => {
            root.flick(0, -event.angleDelta.y * 5);
        }
    }

    focus: true
    Keys.onUpPressed: root.flick(0, 500)
    Keys.onDownPressed: root.flick(0, -500)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) {
            root.flick(0, 2000);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            root.flick(0, -2000);
            event.accepted = true;
        }
    }

    ScrollBar.vertical: ScrollBar {
        id: vbar
        policy: ScrollBar.AsNeeded
        width: 6
        active: root.moving || root.flicking || edgeScrollArea.containsMouse
    }

    MouseArea {
        id: edgeScrollArea
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 20
        hoverEnabled: true
        preventStealing: true
        z: 100

        property real lastY: 0

        onEntered: {
            lastY = mouseY;
            vbar.active = true;
        }

        onPositionChanged: {
            var delta = mouseY - lastY;
            if (Math.abs(delta) > 2) {
                root.flick(0, -delta * 100);
                lastY = mouseY;
            }
        }
    }

    Column {
        id: contentContainer
        width: parent.width
    }
}
