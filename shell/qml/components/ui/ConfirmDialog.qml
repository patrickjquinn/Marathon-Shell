import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Item {
    id: confirmDialog
    anchors.fill: parent
    visible: false
    z: 2500

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

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#000000"
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                cancelled();
                if (onCancel)
                    onCancel();
                hide();
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

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.05)
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
                    text: title
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightBold
                    font.family: MTypography.fontFamily
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: message
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

                MButton {
                    text: cancelText
                    variant: "secondary"
                    width: (parent.width - MSpacing.md) / 2
                    onClicked: {
                        cancelled();
                        if (onCancel)
                            onCancel();
                        hide();
                    }
                }

                MButton {
                    text: confirmText
                    variant: "primary"
                    width: (parent.width - MSpacing.md) / 2
                    onClicked: {
                        confirmed();
                        if (onConfirm)
                            onConfirm();
                        hide();
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
        onFinished: {
            confirmDialog.visible = false;
        }
    }
}
