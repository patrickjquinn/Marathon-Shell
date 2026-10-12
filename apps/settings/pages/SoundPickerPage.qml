pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: soundPickerPage

    property string soundType: "ringtone"
    property string currentSound: ""
    property var availableSounds: []
    property string pageName: soundType

    signal soundSelected(string path)

    pageTitle: SettingsController.soundTypeLabel(soundType)

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
                            id: soundOption

                            required property var modelData

                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: SettingsManagerCpp.formatSoundName(modelData)
                            Accessible.checked: soundPickerPage.currentSound === modelData
                            Accessible.onPressAction: soundMouseArea.clicked(null)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: soundMouseArea.pressed ? MColors.ripple : (soundPickerPage.currentSound === soundOption.modelData ? MColors.marathonTealGlowMid : "transparent")
                                border.width: soundPickerPage.currentSound === soundOption.modelData ? Constants.borderWidthMedium : 0
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
                                    name: soundPickerPage.currentSound === soundOption.modelData ? "volume-2" : "music"
                                    size: Constants.iconSizeMedium
                                    color: soundPickerPage.currentSound === soundOption.modelData ? MColors.marathonTeal : MColors.textSecondary
                                    z: 2
                                }

                                Text {
                                    anchors.left: soundIcon.right
                                    anchors.leftMargin: MSpacing.md
                                    anchors.right: checkBox.left
                                    anchors.rightMargin: MSpacing.md
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: SettingsManagerCpp.formatSoundName(soundOption.modelData)
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    font.weight: soundPickerPage.currentSound === soundOption.modelData ? Font.DemiBold : Font.Normal
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
                                    color: soundPickerPage.currentSound === soundOption.modelData ? MColors.marathonTeal : "transparent"
                                    border.width: Constants.borderWidthMedium
                                    border.color: soundPickerPage.currentSound === soundOption.modelData ? MColors.marathonTeal : MColors.border
                                    z: 2

                                    Icon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: Constants.iconSizeSmall
                                        color: MColors.background
                                        visible: soundPickerPage.currentSound === soundOption.modelData
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
                                    Logger.info("SoundPickerPage", "Selected sound: " + soundOption.modelData);
                                    soundPickerPage.currentSound = soundOption.modelData;
                                    soundPickerPage.soundSelected(soundOption.modelData);
                                    // AudioManagerCpp is an AudioClient inside the
                                    // marathon-app-runner host process (see
                                    // tools/marathon-app-runner/main.cpp), which exposes
                                    // previewSound; the shell-side singleton with the
                                    // same name does not.
                                    AudioManagerCpp.previewSound(soundOption.modelData);  // qmllint disable missing-property
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
