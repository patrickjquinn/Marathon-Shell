import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    color: MColors.background

    ListView {
        id: contactsList
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        anchors.bottomMargin: MSpacing.md
        spacing: MSpacing.sm
        clip: true

        // Header spacer for top padding
        header: Item {
            width: parent.width
            height: MSpacing.lg
        }

        model: phoneApp.contacts

        delegate: Rectangle {
            width: contactsList.width
            height: Constants.touchTargetLarge
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthThin
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing

            Row {
                anchors.fill: parent
                anchors.margins: MSpacing.md
                spacing: MSpacing.md

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.iconSizeLarge
                    height: Constants.iconSizeLarge
                    radius: Constants.borderRadiusSharp
                    color: MColors.elevated
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing

                    Text {
                        anchors.centerIn: parent
                        text: modelData.name.charAt(0).toUpperCase()
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Bold
                        color: MColors.accent
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing * 3 - Constants.iconSizeLarge - Constants.iconSizeMedium
                    spacing: MSpacing.xs

                    Row {
                        spacing: MSpacing.sm

                        Text {
                            text: modelData.name
                            font.pixelSize: MTypography.sizeBody
                            font.weight: Font.DemiBold
                            color: MColors.text
                        }

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "star"
                            size: Constants.iconSizeSmall
                            color: MColors.accent
                            visible: modelData.favorite
                        }
                    }

                    Text {
                        text: modelData.phone
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                    }
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "phone"
                    size: Constants.iconSizeMedium
                    color: MColors.accent
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    parent.color = MColors.elevated;
                    HapticService.light();
                }
                onReleased: {
                    parent.color = MColors.surface;
                }
                onCanceled: {
                    parent.color = MColors.surface;
                }
                onClicked: {
                    console.log("Call contact:", modelData.name, modelData.phone);
                }
            }
        }
    }
}
