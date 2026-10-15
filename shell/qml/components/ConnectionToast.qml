import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: connectionToast

    property string message: ""
    property string iconName: "wifi"
    property bool shown: false
    property real dragOffset: 0

    function show(msg, icon) {
        message = msg;
        iconName = icon || "wifi";
        hideTimer.stop();
        dragOffset = 0;
        shown = true;
        autoHideTimer.restart();
    }

    function hide() {
        if (!shown)
            return;
        autoHideTimer.stop();
        shown = false;
        dragOffset = 0;
        hideTimer.restart();
    }

    anchors.fill: parent
    z: 2950

    Rectangle {
        id: toast

        anchors.horizontalCenter: parent.horizontalCenter
        y: (connectionToast.shown ? Constants.statusBarHeight + Silica.Theme.paddingSmall : -height) + connectionToast.dragOffset
        width: Math.min(toastRow.width + Silica.Theme.paddingLarge * 2, parent.width - Silica.Theme.paddingSmall * 2)
        height: Silica.Theme.itemSizeSmall
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        visible: connectionToast.shown || hideTimer.running

        Row {
            id: toastRow

            anchors.centerIn: parent
            spacing: Silica.Theme.paddingMedium

            GlyphIcon {
                name: connectionToast.iconName
                size: Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Silica.Label {
                text: connectionToast.message
                color: Silica.Theme.primaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: swipeArea

            property real startY: 0
            property bool dragged: false

            anchors.fill: parent
            onPressed: mouse => {
                startY = mapToItem(connectionToast, mouse.x, mouse.y).y;
                dragged = false;
                autoHideTimer.stop();
            }
            onPositionChanged: mouse => {
                const dy = mapToItem(connectionToast, mouse.x, mouse.y).y - startY;
                if (Math.abs(dy) > Silica.Theme.startDragDistance)
                    dragged = true;
                connectionToast.dragOffset = Math.max(Math.min(0, dy), -toast.height);
            }
            onReleased: {
                if (connectionToast.dragOffset < -Silica.Theme.startDragDistance * 2) {
                    connectionToast.hide();
                } else {
                    connectionToast.dragOffset = 0;
                    autoHideTimer.restart();
                }
            }
            onClicked: {
                if (!dragged)
                    connectionToast.hide();
            }
        }

        Behavior on y {
            enabled: !swipeArea.pressed

            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }
    }

    Timer {
        id: autoHideTimer

        interval: 3000
        onTriggered: connectionToast.hide()
    }

    Timer {
        id: hideTimer

        interval: MMotion.moderate
    }
}
