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
            spacing: 24
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Volume"
                width: parent.width - 48
                
                Column {
                    width: parent.width
                    spacing: 16
                    
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
                    value: "Default"
                    showChevron: true
                }
                
                SettingsListItem {
                    title: "Notification Sound"
                    value: SettingsManager.notificationSound
                    showChevron: true
                }
                
                SettingsListItem {
                    title: "Alarm Sound"
                    value: "Classic"
                    showChevron: true
                }
            }
            
            Item { height: 20 }
        }
    }
}

