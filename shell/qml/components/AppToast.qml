import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// An app's toast (x-marathon-toast; Android's Toast through Deckard): a
// short line at the bottom, over the pill, that goes by itself or with a
// swipe down. Taps elsewhere go through.
Item {
    id: appToast

    property var current: null
    property bool shown: false
    property real dragOffset: 0
    readonly property string appIcon: current ? (current.icon || AppModel.findById(current.appId).icon || "") : ""

    function show(notification) {
        current = notification;
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

        objectName: "appToast"
        anchors.horizontalCenter: parent.horizontalCenter
        y: (appToast.shown ? parent.height - Constants.navBarHeight - Silica.Theme.paddingLarge - height : parent.height) + appToast.dragOffset
        width: Math.min(toastRow.implicitWidth + Silica.Theme.paddingLarge * 2, parent.width - Silica.Theme.horizontalPageMargin * 2)
        height: Math.max(Silica.Theme.itemSizeSmall, toastRow.implicitHeight + Silica.Theme.paddingMedium * 2)
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        visible: appToast.shown || hideTimer.running

        Row {
            id: toastRow

            anchors.centerIn: parent
            spacing: Silica.Theme.paddingMedium

            MAppIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: Silica.Theme.iconSizeSmall
                source: appToast.appIcon
                visible: appToast.appIcon.length > 0
            }

            Silica.Label {
                objectName: "appToastText"
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, appToast.width - Silica.Theme.horizontalPageMargin * 2 - Silica.Theme.paddingLarge * 2 - Silica.Theme.iconSizeSmall - toastRow.spacing)
                text: appToast.current ? [appToast.current.title, appToast.current.body].filter(t => t && t.length > 0).join("\n") : ""
                color: Silica.Theme.primaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: swipeArea

            property real startY: 0

            anchors.fill: parent
            onPressed: mouse => {
                startY = mapToItem(appToast, mouse.x, mouse.y).y;
                autoHideTimer.stop();
            }
            onPositionChanged: mouse => {
                const dy = mapToItem(appToast, mouse.x, mouse.y).y - startY;
                appToast.dragOffset = Math.max(0, Math.min(dy, toast.height * 2));
            }
            onReleased: {
                if (appToast.dragOffset > Silica.Theme.startDragDistance * 2) {
                    appToast.hide();
                } else {
                    appToast.dragOffset = 0;
                    autoHideTimer.restart();
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

    Timer {
        id: autoHideTimer

        interval: 3500
        onTriggered: appToast.hide()
    }

    Timer {
        id: hideTimer

        interval: MMotion.moderate
    }
}
