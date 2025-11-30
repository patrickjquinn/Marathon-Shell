import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core

Modal {
    id: listPickerModal

    property var options: []
    property int selectedIndex: 0

    signal selected(int index, string value)

    Column {
        width: parent.width
        spacing: 0  // No spacing between list items

        Repeater {
            model: options

            Rectangle {
                width: parent.width
                height: Constants.listItemHeight
                color: "transparent"
                radius: Constants.borderRadiusSmall

                // Glass morphism hover effect
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(255, 255, 255, 0.02)
                    opacity: itemMouseArea.pressed ? 1 : 0
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.04)
                    radius: parent.radius

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Press feedback
                Rectangle {
                    anchors.fill: parent
                    color: MColors.marathonTeal
                    opacity: itemMouseArea.pressed ? 0.05 : 0
                    radius: parent.radius

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                }

                transform: Translate {
                    y: itemMouseArea.pressed ? -2 : 0

                    Behavior on y {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: Constants.spacingMedium

                    Text {
                        text: modelData
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.weight: index === selectedIndex ? Font.DemiBold : Font.Normal
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                    }

                    Rectangle {
                        visible: index === selectedIndex
                        width: Constants.iconButtonSize
                        height: Constants.iconButtonSize
                        radius: Constants.borderRadiusSmall
                        color: MColors.marathonTeal
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: Constants.smallIndicatorSize
                            height: Constants.smallIndicatorSize
                            radius: Constants.borderRadiusSmall
                            color: MColors.textPrimary
                            anchors.centerIn: parent
                        }
                    }
                }

                Rectangle {
                    visible: index < options.length - 1
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Constants.spacingMedium
                    height: Constants.dividerHeight
                    color: Qt.rgba(255, 255, 255, 0.08)
                }

                MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent

                    onClicked: {
                        selectedIndex = index;
                        listPickerModal.selected(index, modelData);
                        listPickerModal.close();
                    }
                }
            }
        }
    }
}
