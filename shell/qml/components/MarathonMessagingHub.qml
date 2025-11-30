import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import "."
import MarathonUI.Theme

Item {
    id: messagingHub
    height: 0
    visible: false

    property bool showVertical: false

    Rectangle {
        visible: false
        width: parent.width
        height: parent.height
        color: "#CC000000"
        z: 1

        ListView {
            width: parent.width
            height: parent.height
            model: []
            spacing: 0
            clip: true

            delegate: Rectangle {
                width: ListView.view.width
                height: Constants.touchTargetSmall
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#FFFFFF"
                opacity: 0.1
                radius: Constants.borderRadiusSmall

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: Constants.spacingMedium

                    Icon {
                        name: "bell"
                        size: 28
                        color: MColors.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Constants.spacingXSmall

                        Text {
                            text: modelData.title
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeBody
                            font.weight: Font.Bold
                        }

                        Text {
                            text: modelData.content
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeSmall
                        }
                    }
                }
            }
        }

        Rectangle {
            width: Constants.touchTargetMinimum
            height: Constants.touchTargetMinimum
            radius: Constants.borderRadiusXLarge
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Constants.spacingLarge
            color: "#FFFFFF"
            opacity: 0.2

            Text {
                anchors.centerIn: parent
                text: "▼"
                color: MColors.textPrimary
                font.pixelSize: Constants.fontSizeMedium
            }

            MouseArea {
                anchors.fill: parent
                onClicked: showVertical = false
            }
        }
    }
}
