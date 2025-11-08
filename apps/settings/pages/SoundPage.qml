import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Containers
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
                    
                    Slider {
                        width: parent.width
                        from: 0
                        to: 1
                        value: SystemControlStore.volume / 100.0
                        onMoved: {
                            SystemControlStore.setVolume(value * 100)
                        }
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: parent.availableWidth
                            height: 6
                            radius: 2
                            color: Qt.rgba(255, 255, 255, 0.1)
                            
                            Rectangle {
                                width: parent.width * parent.parent.value
                                height: parent.height
                                radius: parent.radius
                                color: Qt.rgba(20, 184, 166, 0.8)
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: 24
                            height: 24
                            radius: 3
                            color: Qt.rgba(20, 184, 166, 0.9)
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.2)
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
                            
                            Slider {
                                width: parent.width
                                from: 0
                                to: 1
                                value: model.volume
                                enabled: !model.muted
                                onMoved: {
                                    AudioManagerCpp.setStreamVolume(model.streamId, value)
                                }
                                
                                background: Rectangle {
                                    x: parent.leftPadding
                                    y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                    width: parent.availableWidth
                                    height: 6
                                    radius: 2
                                    color: Qt.rgba(255, 255, 255, 0.1)
                                    
                                    Rectangle {
                                        width: parent.width * parent.parent.value
                                        height: parent.height
                                        radius: parent.radius
                                        color: Qt.rgba(20, 184, 166, 0.8)
                                    }
                                }
                                
                                handle: Rectangle {
                                    x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                    y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                    width: 24
                                    height: 24
                                    radius: 3
                                    color: Qt.rgba(20, 184, 166, 0.9)
                                    border.width: 1
                                    border.color: Qt.rgba(255, 255, 255, 0.2)
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
                                        AudioManagerCpp.setStreamMuted(model.streamId, !model.muted)
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
                        soundPage.parent.push(ringtonePickerComponent)
                    }
                }
                
                MSettingsListItem {
                    title: "Notification Sound"
                    value: AudioManager.currentNotificationSoundName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(notificationSoundPickerComponent)
                    }
                }
                
                MSettingsListItem {
                    title: "Alarm Sound"
                    value: AudioManager.currentAlarmSoundName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(alarmSoundPickerComponent)
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    Component {
        id: ringtonePickerComponent
        SoundPickerPage {
            soundType: "ringtone"
            currentSound: AudioManager.currentRingtone
            availableSounds: AudioManager.availableRingtones
            onSoundSelected: (path) => {
                AudioManager.setRingtone(path)
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
            onSoundSelected: (path) => {
                AudioManager.setNotificationSound(path)
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
            onSoundSelected: (path) => {
                AudioManager.setAlarmSound(path)
            }
            onNavigateBack: soundPage.parent.pop()
        }
    }
}

