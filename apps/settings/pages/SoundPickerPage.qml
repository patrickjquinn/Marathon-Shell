import QtQuick
import QtQuick.Controls
import QtMultimedia
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: soundPickerPage
    
    property string soundType: "ringtone"
    property string currentSound: ""
    property var availableSounds: []
    
    signal soundSelected(string path)
    
    pageTitle: {
        if (soundType === "ringtone") return "Ringtone"
        if (soundType === "notification") return "Notification Sound"
        if (soundType === "alarm") return "Alarm Sound"
        return "Sound"
    }
    
    property string pageName: soundType
    
    content: Flickable {
        contentHeight: soundContent.height + Constants.spacingXLarge * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: soundContent
            width: parent.width
            spacing: Constants.spacingLarge
            leftPadding: Constants.spacingLarge
            rightPadding: Constants.spacingLarge
            topPadding: Constants.spacingLarge
            
            Text {
                text: "Tap a sound to preview it"
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeBody
                font.family: Typography.fontFamily
                width: parent.width - Constants.spacingLarge * 2
            }
            
            Section {
                title: "Available Sounds"
                width: parent.width - Constants.spacingLarge * 2
                
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
                                color: soundMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : 
                                       (soundPickerPage.currentSound === modelData ? Qt.rgba(20, 184, 166, 0.08) : "transparent")
                                border.width: soundPickerPage.currentSound === modelData ? Constants.borderWidthMedium : 0
                                border.color: Colors.accent
                                
                                Behavior on color {
                                    ColorAnimation { duration: Constants.animationDurationFast }
                                }
                            }
                            
                            Item {
                                width: parent.width
                                height: parent.height
                                
                                Icon {
                                    id: soundIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: Constants.spacingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: soundPickerPage.currentSound === modelData ? "volume-2" : "music"
                                    size: Constants.iconSizeMedium
                                    color: soundPickerPage.currentSound === modelData ? Colors.accent : Colors.textSecondary
                                    z: 2
                                }
                                
                                Text {
                                    anchors.left: soundIcon.right
                                    anchors.leftMargin: Constants.spacingMedium
                                    anchors.right: checkBox.left
                                    anchors.rightMargin: Constants.spacingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: SettingsManagerCpp.formatSoundName(modelData)
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeBody
                                    font.family: Typography.fontFamily
                                    font.weight: soundPickerPage.currentSound === modelData ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    z: 1
                                }
                                
                                Rectangle {
                                    id: checkBox
                                    anchors.right: parent.right
                                    anchors.rightMargin: Constants.spacingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeMedium
                                    height: Constants.iconSizeMedium
                                    radius: Constants.iconSizeMedium / 2
                                    color: soundPickerPage.currentSound === modelData ? Colors.accent : "transparent"
                                    border.width: Constants.borderWidthMedium
                                    border.color: soundPickerPage.currentSound === modelData ? Colors.accent : Colors.border
                                    z: 2
                                    
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: Constants.iconSizeSmall
                                        color: Colors.backgroundDark
                                        visible: soundPickerPage.currentSound === modelData
                                    }
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationDurationFast }
                                    }
                                }
                            }
                            
                            MouseArea {
                                id: soundMouseArea
                                anchors.fill: parent
                                onClicked: {
                                    Logger.info("SoundPickerPage", "Selected sound: " + modelData)
                                    soundPickerPage.currentSound = modelData
                                    soundPickerPage.soundSelected(modelData)
                                }
                            }
                        }
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

