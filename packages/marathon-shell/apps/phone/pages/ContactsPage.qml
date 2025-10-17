import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    color: MColors.background
    
    ListView {
        id: contactsList
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        spacing: Constants.spacingSmall
        clip: true
        
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
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.iconSizeLarge
                    height: Constants.iconSizeLarge
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface2
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Text {
                        anchors.centerIn: parent
                        text: modelData.name.charAt(0).toUpperCase()
                        font.pixelSize: Constants.fontSizeLarge
                        font.weight: Font.Bold
                        color: MColors.accent
                    }
                }
                
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing * 3 - Constants.iconSizeLarge - Constants.iconSizeMedium
                    spacing: Constants.spacingXSmall
                    
                    Row {
                        spacing: Constants.spacingSmall
                        
                        Text {
                            text: modelData.name
                            font.pixelSize: Constants.fontSizeMedium
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
                        font.pixelSize: Constants.fontSizeSmall
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
                    parent.color = MColors.surface2
                    HapticService.light()
                }
                onReleased: {
                    parent.color = MColors.surface
                }
                onCanceled: {
                    parent.color = MColors.surface
                }
                onClicked: {
                    console.log("Call contact:", modelData.name, modelData.phone)
                }
            }
        }
    }
}

