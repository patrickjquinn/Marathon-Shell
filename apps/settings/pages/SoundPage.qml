pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

SettingsPageTemplate {
    id: soundPage

    property string pageName: "sound"

    pageTitle: "Sound"

    Component {
        id: ringtonePickerComponent

        SoundPickerPage {
            soundType: "ringtone"
            currentSound: SettingsManagerCpp.ringtone
            availableSounds: SettingsManagerCpp.availableRingtones()
            onSoundSelected: path => {
                SettingsManagerCpp.ringtone = path;
            }
            onNavigateBack: StackView.view.pop()
        }
    }

    Component {
        id: notificationSoundPickerComponent

        SoundPickerPage {
            soundType: "notification"
            currentSound: SettingsManagerCpp.notificationSound
            availableSounds: SettingsManagerCpp.availableNotificationSounds()
            onSoundSelected: path => {
                SettingsManagerCpp.notificationSound = path;
            }
            onNavigateBack: StackView.view.pop()
        }
    }

    Component {
        id: alarmSoundPickerComponent

        SoundPickerPage {
            soundType: "alarm"
            currentSound: SettingsManagerCpp.alarmSound
            availableSounds: SettingsManagerCpp.availableAlarmSounds()
            onSoundSelected: path => {
                SettingsManagerCpp.alarmSound = path;
            }
            onNavigateBack: StackView.view.pop()
        }
    }

    content: Flickable {
        contentHeight: soundContent.height + 40
        clip: true

        Column {
            id: soundContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Volume"
                width: parent.width - 48

                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    leftPadding: MSpacing.md
                    rightPadding: MSpacing.md

                    MSlider {
                        width: parent.width - parent.leftPadding - parent.rightPadding
                        from: 0
                        to: 100
                        value: SystemControlStore.volume
                        onMoved: {
                            SystemControlStore.setVolume(value);
                        }
                    }
                }
            }

            MSection {
                title: "Per-App Volume"
                subtitle: AudioManagerCpp.perAppVolumeSupported ? "Control individual app volumes" : "Requires PipeWire"
                width: parent.width - 48
                visible: AudioManagerCpp.perAppVolumeSupported

                Repeater {
                    // AudioStreamModel is registered via the AudioClient IPC
                    // shim in marathon-app-runner; its qmltypes is not present
                    // when linting against MarathonOS.Shell so qmllint can't
                    // resolve the type. Runtime is correct.
                    model: AudioManagerCpp.streams  // qmllint disable unresolved-type

                    Column {
                        id: streamDelegate

                        required property var model

                        width: parent.width
                        spacing: MSpacing.sm
                        padding: MSpacing.md

                        Text {
                            width: parent.width - parent.padding * 2
                            text: streamDelegate.model.appName + " · " + Math.round(streamDelegate.model.volume * 100) + "%" + (streamDelegate.model.muted ? " (Muted)" : "")
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeSubhead
                            font.family: MTypography.fontFamily
                            elide: Text.ElideRight
                        }

                        Row {
                            width: parent.width - parent.padding * 2
                            spacing: MSpacing.sm

                            MSlider {
                                width: parent.width - muteButton.width - MSpacing.sm
                                anchors.verticalCenter: parent.verticalCenter
                                from: 0
                                to: 1
                                value: streamDelegate.model.volume
                                disabled: streamDelegate.model.muted
                                onMoved: {
                                    AudioManagerCpp.setStreamVolume(streamDelegate.model.streamId, value);
                                }
                            }

                            MButton {
                                id: muteButton

                                text: streamDelegate.model.muted ? "Unmute" : "Mute"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    AudioManagerCpp.setStreamMuted(streamDelegate.model.streamId, !streamDelegate.model.muted);
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "No audio streams playing"
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                    visible: AudioManagerCpp.streams.rowCount() === 0  // qmllint disable unresolved-type
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: MSpacing.md
                    bottomPadding: MSpacing.md
                }
            }

            MSection {
                title: "Sounds"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Ringtone"
                    value: SettingsManagerCpp.formatSoundName(SettingsManagerCpp.ringtone)
                    showChevron: true
                    onSettingClicked: {
                        soundPage.StackView.view.push(ringtonePickerComponent);
                    }
                }

                MSettingsListItem {
                    title: "Notification Sound"
                    value: SettingsManagerCpp.formatSoundName(SettingsManagerCpp.notificationSound)
                    showChevron: true
                    onSettingClicked: {
                        soundPage.StackView.view.push(notificationSoundPickerComponent);
                    }
                }

                MSettingsListItem {
                    title: "Alarm Sound"
                    value: SettingsManagerCpp.formatSoundName(SettingsManagerCpp.alarmSound)
                    showChevron: true
                    onSettingClicked: {
                        soundPage.StackView.view.push(alarmSoundPickerComponent);
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
