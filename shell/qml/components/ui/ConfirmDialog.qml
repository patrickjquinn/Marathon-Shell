import MarathonUI.Core
import MarathonUI.Effects
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
        width: Math.min(parent.width - 64, 400)
        height: contentColumn.height + MSpacing.touchTargetLarge
        radius: MRadius.md
        color: Qt.rgba(15, 15, 15, 0.98)
        border.width: 1
        border.color: MColors.border
        layer.enabled: true
        opacity: 0
        scale: 0.9

        MTopHairline {
            radius: parent.radius
            color: Qt.rgba(255, 255, 255, 0.05)
            lineWidth: 1
        }

        Column {
            id: contentColumn

            anchors.centerIn: parent
            width: parent.width - MSpacing.touchTargetLarge
            spacing: MSpacing.xl

            Column {
                width: parent.width
                spacing: MSpacing.md

                Text {
                    text: confirmDialog.title
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightBold
                    font.family: MTypography.fontFamily
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: confirmDialog.message
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                width: parent.width
                spacing: MSpacing.md

                Silica.Button {
                    text: confirmDialog.cancelText
                    backgroundColor: "transparent"
                    border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, Silica.Theme.opacityFaint)
                    width: (parent.width - MSpacing.md) / 2
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
                    width: (parent.width - MSpacing.md) / 2
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

        NumberAnimation {
            target: dialog
            property: "scale"
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

        NumberAnimation {
            target: dialog
            property: "scale"
            to: 0.9
            duration: 150
            easing.type: Easing.InCubic
        }
    }
}
