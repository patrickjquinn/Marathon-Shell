import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core

Modal {
    id: textInputModal

    property alias inputText: textInput.text
    property string placeholderText: ""

    signal accepted(string text)

    Column {
        width: parent.width
        spacing: Constants.spacingMedium

        Rectangle {
            width: parent.width
            height: Constants.inputHeight
            color: MColors.background
            radius: Constants.borderRadiusSmall
            border.width: textInput.activeFocus ? Constants.borderWidthMedium : Constants.borderWidthThin
            border.color: textInput.activeFocus ? MColors.marathonTeal : Qt.rgba(255, 255, 255, 0.1)

            Behavior on border.color {
                ColorAnimation {
                    duration: Constants.animationDurationFast
                }
            }

            TextInput {
                id: textInput
                anchors.fill: parent
                anchors.margins: 12
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true

                Text {
                    visible: !textInput.text && !textInput.activeFocus
                    text: placeholderText
                    color: MColors.textTertiary
                    font: textInput.font
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Row {
            width: parent.width
            height: Constants.statusBarHeight
            spacing: Constants.spacingMedium
            z: 10

            Rectangle {
                width: (parent.width - 12) / 2
                height: Constants.statusBarHeight
                color: MColors.surface
                radius: Constants.borderRadiusSmall
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(255, 255, 255, 0.08)

                transform: Translate {
                    y: cancelMouseArea.pressed ? -2 : 0
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Text {
                    text: "Cancel"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: cancelMouseArea
                    anchors.fill: parent

                    z: 20
                    onClicked: {
                        console.log("Cancel clicked");
                        textInputModal.close();
                    }
                }
            }

            Rectangle {
                width: (parent.width - Constants.spacingSmall) / 2
                height: Constants.statusBarHeight
                radius: Constants.borderRadiusSmall
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(20, 184, 166, 0.4)

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(20, 184, 166, 0.78)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(20, 184, 166, 0.35)
                    }
                }

                transform: Translate {
                    y: saveMouseArea.pressed ? -2 : 0
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                // Glow effect on hover
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: saveMouseArea.pressed ? 1 : 0
                    border.color: Qt.rgba(20, 184, 166, 0.3)
                    opacity: saveMouseArea.pressed ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }

                Text {
                    text: "Save"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.DemiBold
                    font.family: MTypography.fontFamily
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: saveMouseArea
                    anchors.fill: parent

                    z: 20
                    onClicked: {
                        console.log("Save clicked, text:", textInput.text);
                        textInputModal.accepted(textInput.text);
                        textInputModal.close();
                    }
                }
            }
        }
    }
}
