import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Theme
import "../components"

SettingsPageTemplate {
    id: soundPage
    pageTitle: "Sound"

    property string pageName: "sound"

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
                    model: AudioManagerCpp.streams

                    MSettingsListItem {
                        title: model.appName
                        subtitle: Math.round(model.volume * 100) + "%" + (model.muted ? " (Muted)" : "")
                        showToggle: false

                        Column {
                            width: parent.width
                            spacing: MSpacing.sm
                            leftPadding: MSpacing.md
                            rightPadding: MSpacing.md

                            MSlider {
                                width: parent.width - parent.leftPadding - parent.rightPadding
                                from: 0
                                to: 1
                                value: model.volume
                                disabled: model.muted
                                onMoved: {
                                    AudioManagerCpp.setStreamVolume(model.streamId, value);
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: MSpacing.sm

                                MButton {
                                    text: model.muted ? "Unmute" : "Mute"
                                    width: 100
                                    height: 32
                                    onClicked: {
                                        AudioManagerCpp.setStreamMuted(model.streamId, !model.muted);
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "No audio streams playing"
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSmall
                    visible: AudioManagerCpp.streams.rowCount() === 0
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
                    value: AudioManager.currentRingtoneName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(ringtonePickerComponent);
                    }
                }

                MSettingsListItem {
                    title: "Notification Sound"
                    value: AudioManager.currentNotificationSoundName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(notificationSoundPickerComponent);
                    }
                }

                MSettingsListItem {
                    title: "Alarm Sound"
                    value: AudioManager.currentAlarmSoundName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(alarmSoundPickerComponent);
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }

    Component {
        id: ringtonePickerComponent
        SoundPickerPage {
            soundType: "ringtone"
            currentSound: AudioManager.currentRingtone
            availableSounds: AudioManager.availableRingtones
            onSoundSelected: path => {
                AudioManager.setRingtone(path);
            }
            onNavigateBack: soundPage.parent.pop()
        }
    }

    Component {
        id: notificationSoundPickerComponent
        SoundPickerPage {
            soundType: "notification"
            currentSound: AudioManager.currentNotificationSound
            availableSounds: AudioManager.availableNotificationSounds
            onSoundSelected: path => {
                AudioManager.setNotificationSound(path);
            }
            onNavigateBack: soundPage.parent.pop()
        }
    }

    Component {
        id: alarmSoundPickerComponent
        SoundPickerPage {
            soundType: "alarm"
            currentSound: AudioManager.currentAlarmSound
            availableSounds: AudioManager.availableAlarmSounds
            onSoundSelected: path => {
                AudioManager.setAlarmSound(path);
            }
            onNavigateBack: soundPage.parent.pop()
        }
    }
}
