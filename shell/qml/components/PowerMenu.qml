import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: powerMenu
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.85)
    visible: false
    z: Constants.zIndexModal + 100  // Above everything
    
    signal rebootRequested()
    signal shutdownRequested()
    signal sleepRequested()
    signal canceled()
    
    function show() {
        visible = true
        HapticService.medium()
    }
    
    function hide() {
        visible = false
    }
    
    // Click outside to dismiss
    MouseArea {
        anchors.fill: parent
        onClicked: {
            powerMenu.canceled()
            powerMenu.hide()
        }
    }
    
    // Power menu dialog
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 320)
        height: contentColumn.height + 48
        radius: Constants.borderRadiusLarge
        color: MColors.surface
        border.width: 1
        border.color: MColors.borderOuter
        
        Column {
            id: contentColumn
            width: parent.width - 48
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            spacing: Constants.spacingMedium
            
            Text {
                text: "Power Options"
                color: MColors.text
                font.pixelSize: Constants.fontSizeLarge
                font.weight: Font.Bold
                font.family: Typography.fontFamily
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            // Sleep
            Rectangle {
                width: parent.width
                height: 60
                radius: Constants.borderRadiusSmall
                color: sleepMouseArea.pressed ? MColors.surfaceDark : "transparent"
                border.width: 1
                border.color: MColors.borderOuter
                
                Row {
                    anchors.centerIn: parent
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        name: "moon"
                        size: Constants.iconSizeMedium
                        color: MColors.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: "Sleep"
                        color: MColors.text
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    id: sleepMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium()
                        powerMenu.sleepRequested()
                        powerMenu.hide()
                    }
                }
            }
            
            // Reboot
            Rectangle {
                width: parent.width
                height: 60
                radius: Constants.borderRadiusSmall
                color: rebootMouseArea.pressed ? MColors.surfaceDark : "transparent"
                border.width: 1
                border.color: MColors.borderOuter
                
                Row {
                    anchors.centerIn: parent
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        name: "rotate-ccw"
                        size: Constants.iconSizeMedium
                        color: MColors.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: "Reboot"
                        color: MColors.warning
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    id: rebootMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium()
                        powerMenu.rebootRequested()
                        powerMenu.hide()
                    }
                }
            }
            
            // Shutdown
            Rectangle {
                width: parent.width
                height: 60
                radius: Constants.borderRadiusSmall
                color: shutdownMouseArea.pressed ? MColors.surfaceDark : "transparent"
                border.width: 1
                border.color: MColors.borderOuter
                
                Row {
                    anchors.centerIn: parent
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        name: "zap"
                        size: Constants.iconSizeMedium
                        color: MColors.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: "Power Off"
                        color: MColors.error
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    id: shutdownMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium()
                        powerMenu.shutdownRequested()
                        powerMenu.hide()
                    }
                }
            }
            
            // Cancel button
            Rectangle {
                width: parent.width
                height: 50
                radius: Constants.borderRadiusSmall
                color: cancelMouseArea.pressed ? MColors.accentDark : MColors.accent
                
                Text {
                    text: "Cancel"
                    color: MColors.textOnAccent
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.DemiBold
                    font.family: MTypography.fontFamily
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: cancelMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light()
                        powerMenu.canceled()
                        powerMenu.hide()
                    }
                }
            }
        }
    }
}

