import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: confirmDialog

    property string title: ""
    property string message: ""
    property string confirmText: "Confirm"
    property string cancelText: "Cancel"
    property var onConfirm: null
    property var onCancel: null

    signal confirmed
    signal cancelled

    function show(titleText, messageText, confirmCallback) {
        title = titleText;
        message = messageText;
        onConfirm = confirmCallback;
        visible = true;
        fadeIn.start();
    }

    function hide() {
        fadeOut.start();
    }

    anchors.fill: parent
    visible: false
    z: 2500

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: "#000000"
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                confirmDialog.cancelled();
                var callback = confirmDialog.onCancel;
                if (callback)
                    callback();

                confirmDialog.hide();
            }
        }
    }

    Rectangle {
        id: dialog

        anchors.centerIn: parent
        width: parent.width - Silica.Theme.horizontalPageMargin * 2
        height: contentColumn.height + Silica.Theme.paddingLarge * 2
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        opacity: 0

        Column {
            id: contentColumn

            anchors.centerIn: parent
            width: parent.width - Silica.Theme.paddingLarge * 2
            spacing: Silica.Theme.paddingLarge

            Column {
                width: parent.width
                spacing: Silica.Theme.paddingSmall

                Silica.Label {
                    text: confirmDialog.title
                    color: Silica.Theme.highlightColor
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    font.family: Silica.Theme.fontFamilyHeading
                    width: parent.width
                    wrapMode: Text.Wrap
                }

                Silica.Label {
                    text: confirmDialog.message
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    width: parent.width
                    wrapMode: Text.Wrap
                }
            }

            Row {
                width: parent.width
                spacing: Silica.Theme.paddingMedium

                Silica.Button {
                    text: confirmDialog.cancelText
                    width: (parent.width - Silica.Theme.paddingMedium) / 2
                    onClicked: {
                        confirmDialog.cancelled();
                        var callback = confirmDialog.onCancel;
                        if (callback)
                            callback();

                        confirmDialog.hide();
                    }
                }

                Silica.Button {
                    text: confirmDialog.confirmText
                    width: (parent.width - Silica.Theme.paddingMedium) / 2
                    onClicked: {
                        confirmDialog.confirmed();
                        var callback = confirmDialog.onConfirm;
                        if (callback)
                            callback();

                        confirmDialog.hide();
                    }
                }
            }
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: backdrop
            property: "opacity"
            to: 0.7
            duration: 200
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: dialog
            property: "opacity"
            to: 1
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: fadeOut

        onFinished: {
            confirmDialog.visible = false;
        }

        NumberAnimation {
            target: backdrop
            property: "opacity"
            to: 0
            duration: 150
            easing.type: Easing.InCubic
        }

        NumberAnimation {
            target: dialog
            property: "opacity"
            to: 0
            duration: 150
            easing.type: Easing.InCubic
        }
    }
}
