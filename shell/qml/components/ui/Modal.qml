import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Rectangle {
    id: modal

    property alias title: modalTitle.text
    default property alias content: contentArea.children

    signal closed

    function open() {
        visible = true;
        openAnimation.start();
    }

    function close() {
        closeAnimation.start();
    }

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.7)
    visible: false
    opacity: 0
    z: 2000

    NumberAnimation {
        id: openAnimation

        target: modal
        property: "opacity"
        from: 0
        to: 1
        duration: Constants.animationDurationNormal
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: closeAnimation

        NumberAnimation {
            target: modal
            property: "opacity"
            from: 1
            to: 0
            duration: Constants.animationDurationFast
            easing.type: Easing.InCubic
        }

        PropertyAction {
            target: modal
            property: "visible"
            value: false
        }

        ScriptAction {
            script: modal.closed()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: modal.close()
        z: 1
    }

    Rectangle {
        id: modalCard

        anchors.centerIn: parent
        width: parent.width - Silica.Theme.horizontalPageMargin * 2
        height: Math.min(modalColumn.height + Silica.Theme.paddingLarge * 2, parent.height - Silica.Theme.itemSizeLarge * 2)
        color: Silica.Theme.rgba("black", 0.85)
        radius: Silica.Theme.paddingMedium
        z: 2
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)

        Column {
            id: modalColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingLarge

            Item {
                id: modalHeader

                width: parent.width
                height: Silica.Theme.itemSizeSmall

                Silica.Label {
                    id: modalTitle

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: Silica.Theme.highlightColor
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    font.family: Silica.Theme.fontFamilyHeading
                    truncationMode: Silica.TruncationMode.Fade
                    width: parent.width - closeButton.width - Silica.Theme.paddingSmall
                }

                Silica.IconButton {
                    id: closeButton

                    icon.source: "image://theme/icon-m-close"
                    Accessible.name: "Close"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        Logger.info("Modal", "Close button clicked");
                        modal.close();
                    }
                }
            }

            Item {
                id: contentArea

                width: parent.width
                height: childrenRect.height
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 5
            onClicked: {
                console.log("Modal card clicked (blocking background)");
            }
        }
    }
}
