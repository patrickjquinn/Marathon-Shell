import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Marathon DS · Thread composer (screens-apps-1.jsx:MessagesThread).
//
// Glass-tabbar surface, 70 px tall. 36×36 elev-2 "+" plug-in
// attachments button on the left, "iMessage" placeholder input with
// elev-2 fill and 18 px radius, 48×48 teal-gradient send button right.
Rectangle {
    id: root

    property alias text: messageInput.text
    property alias placeholderText: messageInput.placeholderText
    property int maxLength: 1000

    signal sendMessage(string text)
    signal attachPressed

    width: parent ? parent.width : 0
    height: 70
    color: MColors.glassTabbar

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: MColors.borderGlass
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 10

        // 36 × 36 attach (+) button — elev-2 circle with subtle border.
        Rectangle {
            id: attachButton
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: width / 2
            color: attachArea.pressed ? MColors.bb10Card : MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04

            Icon {
                anchors.centerIn: parent
                name: "plus"
                size: 18
                color: MColors.textPrimary
            }

            Behavior on color {
                ColorAnimation {
                    duration: 80
                }
            }

            MouseArea {
                id: attachArea
                anchors.fill: parent
                onClicked: {
                    HapticService.light();
                    root.attachPressed();
                }
            }
        }

        // Input field — flexes to fill remaining width.
        Rectangle {
            id: inputContainer
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - attachButton.width - sendButton.width - parent.spacing * 2
            height: 36
            radius: 18
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04

            TextField {
                id: messageInput
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                placeholderText: "iMessage"
                color: MColors.textPrimary
                placeholderTextColor: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeBody
                background: null
                selectByMouse: true
                Keys.onReturnPressed: {
                    if (text.trim().length > 0) {
                        root.sendMessage(text);
                        text = "";
                    }
                }
            }
        }

        // 48 × 48 send button — teal-gradient with halo when active.
        Rectangle {
            id: sendButton
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: width / 2
            border.width: 1
            border.color: MColors.tealBorder
            opacity: messageInput.text.trim().length > 0 ? 1 : 0.4

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
                border.color: Qt.rgba(1, 1, 1, 0.3)
            }

            Icon {
                anchors.centerIn: parent
                name: "send"
                size: 20
                color: "#000000"
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
                enabled: messageInput.text.trim().length > 0
                onClicked: {
                    HapticService.medium();
                    root.sendMessage(messageInput.text);
                    messageInput.text = "";
                }
            }
        }
    }
}
