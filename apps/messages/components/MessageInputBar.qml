import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Controls

Rectangle {
    id: root

    property alias text: messageInput.text
    property alias placeholderText: messageInput.placeholderText
    property int maxLength: 160
    property bool showCharCount: text.length > maxLength * 0.8

    signal sendMessage(string text)
    signal attachPressed

    width: parent.width
    height: Math.max(64, contentColumn.height + MSpacing.md * 2)
    color: MColors.surface

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: MColors.border
    }

    Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: MSpacing.md
        spacing: MSpacing.xs

        Row {
            width: parent.width
            spacing: MSpacing.sm

            MIconButton {
                id: attachButton
                anchors.verticalCenter: parent.verticalCenter
                iconName: "paperclip"
                iconSize: 20
                variant: "ghost"
                onClicked: {
                    HapticService.light();
                    root.attachPressed();
                }
            }

            MTextInput {
                id: messageInput
                width: parent.width - attachButton.width - sendButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Type a message..."

                Keys.onReturnPressed: {
                    if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false;
                    } else if (text.trim().length > 0) {
                        event.accepted = true;
                        root.sendMessage(text);
                        text = "";
                    }
                }
            }

            MIconButton {
                id: sendButton
                anchors.verticalCenter: parent.verticalCenter
                iconName: "send"
                iconSize: 20
                variant: messageInput.text.trim().length > 0 ? "primary" : "ghost"
                enabled: messageInput.text.trim().length > 0
                onClicked: {
                    if (messageInput.text.trim().length > 0) {
                        HapticService.medium();
                        root.sendMessage(messageInput.text);
                        messageInput.text = "";
                    }
                }
            }
        }

        MLabel {
            visible: showCharCount
            text: messageInput.text.length + " / " + maxLength
            variant: messageInput.text.length > maxLength ? "error" : "tertiary"
            font.pixelSize: MTypography.sizeXSmall
            anchors.right: parent.right
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: MMotion.fast
            easing.bezierCurve: MMotion.easingStandardCurve
        }
    }
}
