import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Core
import "../components"

SettingsPageTemplate {
    id: soundPickerPage

    property string soundType: "ringtone"
    property string currentSound: ""
    property var availableSounds: []

    signal soundSelected(string path)

    pageTitle: {
        if (soundType === "ringtone")
            return "Ringtone";
        if (soundType === "notification")
            return "Notification Sound";
        if (soundType === "alarm")
            return "Alarm Sound";
        return "Sound";
    }

    property string pageName: soundType

    content: Flickable {
        contentHeight: soundContent.height + MSpacing.xl * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: soundContent
            width: parent.width
            spacing: MSpacing.lg
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            Text {
                text: "Tap a sound to preview it"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                width: parent.width - MSpacing.lg * 2
            }

            MSection {
                title: "Available Sounds"
                width: parent.width - MSpacing.lg * 2

                Column {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: soundPickerPage.availableSounds

                        Rectangle {
                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: soundMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : (soundPickerPage.currentSound === modelData ? Qt.rgba(20, 184, 166, 0.08) : "transparent")
                                border.width: soundPickerPage.currentSound === modelData ? Constants.borderWidthMedium : 0
                                border.color: MColors.marathonTeal

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Constants.animationDurationFast
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: parent.height

                                Icon {
                                    id: soundIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: MSpacing.md
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: soundPickerPage.currentSound === modelData ? "volume-2" : "music"
                                    size: Constants.iconSizeMedium
                                    color: soundPickerPage.currentSound === modelData ? MColors.marathonTeal : MColors.textSecondary
                                    z: 2
                                }

                                Text {
                                    anchors.left: soundIcon.right
                                    anchors.leftMargin: MSpacing.md
                                    anchors.right: checkBox.left
                                    anchors.rightMargin: MSpacing.md
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: SettingsManagerCpp.formatSoundName(modelData)
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    font.weight: soundPickerPage.currentSound === modelData ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    z: 1
                                }

                                Rectangle {
                                    id: checkBox
                                    anchors.right: parent.right
                                    anchors.rightMargin: MSpacing.md
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeMedium
                                    height: Constants.iconSizeMedium
                                    radius: Constants.iconSizeMedium / 2
                                    color: soundPickerPage.currentSound === modelData ? MColors.marathonTeal : "transparent"
                                    border.width: Constants.borderWidthMedium
                                    border.color: soundPickerPage.currentSound === modelData ? MColors.marathonTeal : MColors.border
                                    z: 2

                                    Icon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: Constants.iconSizeSmall
                                        color: MColors.background
                                        visible: soundPickerPage.currentSound === modelData
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Constants.animationDurationFast
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: soundMouseArea
                                anchors.fill: parent
                                onClicked: {
                                    Logger.info("SoundPickerPage", "Selected sound: " + modelData);

                                    // Save selection
                                    soundPickerPage.currentSound = modelData;
                                    soundPickerPage.soundSelected(modelData);

                                    // Preview the sound using dedicated preview player
                                    if (soundPickerPage.soundType === "ringtone") {
                                        AudioManager.previewRingtone(modelData);
                                    } else if (soundPickerPage.soundType === "notification") {
                                        AudioManager.previewNotificationSound(modelData);
                                    } else if (soundPickerPage.soundType === "alarm") {
                                        AudioManager.previewAlarmSound(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
