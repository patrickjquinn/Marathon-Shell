import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Marathon DS · Thread composer (screens-apps-1.jsx:MessagesThread).
//
// Glass-tabbar surface. "Message" input with elev-2 fill and pill
// radius, teal-gradient send button right. The text is kept until the
// caller clears it, so a failed send never loses what was typed.
Rectangle {
    id: root

    property alias text: messageInput.text
    property alias placeholderText: messageInput.placeholderText
    property bool sending: false

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real controlSize: Math.round(44 * scaleFactor)
    readonly property bool canSend: !sending && messageInput.text.trim().length > 0

    signal sendMessage(string text)

    function send() {
        if (!canSend)
            return;
        HapticService.medium();
        sendMessage(messageInput.text);
    }

    width: parent ? parent.width : 0
    height: controlSize + MSpacing.md * 2
    color: MColors.glassTabbar

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: MColors.borderGlass
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.sm

        // Input field — flexes to fill remaining width.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - sendButton.width - parent.spacing
            height: root.controlSize
            radius: height / 2
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04

            TextField {
                id: messageInput
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                verticalAlignment: TextInput.AlignVCenter
                placeholderText: "Message"
                color: MColors.textPrimary
                placeholderTextColor: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeBody
                background: null
                selectByMouse: true
                Keys.onReturnPressed: root.send()
            }
        }

        Rectangle {
            id: sendButton
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(48 * root.scaleFactor)
            height: width
            radius: width / 2
            border.width: 1
            border.color: MColors.tealBorder
            opacity: root.canSend ? 1 : 0.4

            Accessible.role: Accessible.Button
            Accessible.name: root.sending ? "Sending" : "Send message"
            Accessible.onPressAction: root.send()

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: MColors.marathonTealBright
                }
                GradientStop {
                    position: 1
                    color: MColors.marathonTealDark
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: MColors.whiteOverlay30
            }

            Icon {
                anchors.centerIn: parent
                name: "send"
                size: Math.round(20 * root.scaleFactor)
                color: MColors.textOnAccent
            }

            scale: sendArea.pressed ? 0.94 : 1.0
            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutBack
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }

            MouseArea {
                id: sendArea
                anchors.fill: parent
                enabled: root.canSend
                onClicked: root.send()
            }
        }
    }
}
