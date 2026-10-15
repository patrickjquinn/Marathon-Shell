import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: errorToast

    property string errorMessage: ""
    property string errorTitle: ""
    property string errorIcon: "alert-circle"
    property int displayDuration: 5000
    property bool shown: false
    property real dragOffset: 0

    signal dismissed

    function show(title, message, icon) {
        errorTitle = title || "Error";
        errorMessage = message;
        errorIcon = icon || "alert-circle";
        hideTimer.stop();
        dragOffset = 0;
        shown = true;
        dismissTimer.restart();
        HapticManager.medium();
        Logger.warn("ErrorToast", title + ": " + message);
    }

    function hide() {
        if (!shown)
            return;
        dismissTimer.stop();
        shown = false;
        dragOffset = 0;
        hideTimer.restart();
    }

    anchors.fill: parent
    z: 2500

    Timer {
        id: dismissTimer

        interval: errorToast.displayDuration
        onTriggered: errorToast.hide()
    }

    Timer {
        id: hideTimer

        interval: MMotion.moderate
        onTriggered: errorToast.dismissed()
    }

    Rectangle {
        id: errorCard

        anchors.horizontalCenter: parent.horizontalCenter
        y: (errorToast.shown ? Constants.statusBarHeight + Silica.Theme.paddingSmall : -height) + errorToast.dragOffset
        width: parent.width - Silica.Theme.paddingSmall * 2
        height: errorContent.height + Silica.Theme.paddingMedium * 2
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        visible: errorToast.shown || hideTimer.running

        MouseArea {
            id: swipeArea

            property real startY: 0
            property bool dragged: false

            anchors.fill: parent
            onPressed: mouse => {
                startY = mapToItem(errorToast, mouse.x, mouse.y).y;
                dragged = false;
                dismissTimer.stop();
            }
            onPositionChanged: mouse => {
                const dy = mapToItem(errorToast, mouse.x, mouse.y).y - startY;
                if (Math.abs(dy) > Silica.Theme.startDragDistance)
                    dragged = true;
                errorToast.dragOffset = Math.max(Math.min(0, dy), -errorCard.height);
            }
            onReleased: {
                if (errorToast.dragOffset < -Silica.Theme.startDragDistance * 2) {
                    errorToast.hide();
                } else {
                    errorToast.dragOffset = 0;
                    dismissTimer.restart();
                }
            }
            onClicked: {
                if (!dragged)
                    errorToast.hide();
            }
        }

        Column {
            id: errorContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Silica.Theme.paddingMedium
            anchors.rightMargin: 0

            Row {
                width: parent.width
                spacing: Silica.Theme.paddingMedium

                GlyphIcon {
                    id: errorGlyph

                    name: errorToast.errorIcon
                    size: Silica.Theme.iconSizeSmallPlus
                    color: Silica.Theme.errorColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    width: parent.width - errorGlyph.width - closeButton.width - Silica.Theme.paddingMedium * 2
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        text: errorToast.errorTitle
                        color: Silica.Theme.primaryColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        truncationMode: Silica.TruncationMode.Fade
                        width: parent.width
                    }

                    Silica.Label {
                        text: errorToast.errorMessage
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                        width: parent.width
                        wrapMode: Text.Wrap
                        visible: errorToast.errorMessage.length > 0
                    }
                }

                Silica.IconButton {
                    id: closeButton

                    icon.source: "image://theme/icon-m-close"
                    Accessible.name: "Close"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        HapticManager.light();
                        errorToast.hide();
                    }
                }
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
}
