import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
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
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Volume"
                width: parent.width - 48
                
                Column {
                    width: parent.width
                    spacing: Constants.spacingMedium
                    
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
            
            Section {
                title: "Sounds"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Ringtone"
                    value: AudioManager.currentRingtoneName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(ringtonePickerComponent)
                    }
                }
                
                SettingsListItem {
                    title: "Notification Sound"
                    value: AudioManager.currentNotificationSoundName
                    showChevron: true
                    onSettingClicked: {
                        soundPage.parent.push(notificationSoundPickerComponent)
                    }
                }
                
                SettingsListItem {
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

