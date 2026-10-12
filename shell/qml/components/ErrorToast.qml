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

    signal dismissed

    function show(title, message, icon) {
        errorTitle = title || "Error";
        errorMessage = message;
        errorIcon = icon || "alert-circle";
        visible = true;
        showAnimation.start();
        dismissTimer.restart();
        HapticManager.medium();
        Logger.warn("ErrorToast", title + ": " + message);
    }

    function hide() {
        hideAnimation.start();
    }

    anchors.fill: parent
    visible: false
    z: 2500

    Timer {
        id: dismissTimer

        interval: errorToast.displayDuration
        onTriggered: errorToast.hide()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: errorToast.hide()
    }

    Rectangle {
        id: errorCard

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight + Silica.Theme.paddingSmall
        width: parent.width - Silica.Theme.paddingSmall * 2
        height: errorContent.height + Silica.Theme.paddingMedium * 2
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        opacity: 0

        MouseArea {
            id: swipeArea

            anchors.fill: parent
            drag.target: errorCard
            drag.axis: Drag.YAxis
            drag.minimumY: -errorCard.height
            drag.maximumY: 100
            onReleased: function(mouse) {
                if (errorCard.y > 50)
                    errorToast.hide();
                else
                    snapBackAnimation.start();
            }
            onClicked: mouse => mouse.accepted = true
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
    }

    ParallelAnimation {
        id: showAnimation

        NumberAnimation {
            target: errorCard
            property: "opacity"
            from: 0
            to: 1
            duration: 300
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: errorCard
            property: "y"
            from: -errorCard.height
            to: Constants.statusBarHeight + Silica.Theme.paddingSmall
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: hideAnimation

        ParallelAnimation {
            NumberAnimation {
                target: errorCard
                property: "opacity"
                to: 0
                duration: 250
                easing.type: Easing.InQuad
            }

            NumberAnimation {
                target: errorCard
                property: "y"
                to: -errorCard.height
                duration: 300
                easing.type: Easing.InCubic
            }
        }

        ScriptAction {
            script: {
                errorToast.visible = false;
                errorToast.dismissed();
            }
        }
    }

    NumberAnimation {
        id: snapBackAnimation

        target: errorCard
        property: "y"
        to: Constants.statusBarHeight + Silica.Theme.paddingSmall
        duration: 200
        easing.type: Easing.OutQuad
    }
}
