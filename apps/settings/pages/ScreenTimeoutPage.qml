import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: screenTimeoutPage
    pageTitle: "Screen Timeout"
    
    property string pageName: "screentimeout"
    
    content: Flickable {
        contentHeight: timeoutContent.height + Constants.spacingXLarge * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: timeoutContent
            width: parent.width
            spacing: Constants.spacingLarge
            leftPadding: Constants.spacingLarge
            rightPadding: Constants.spacingLarge
            topPadding: Constants.spacingLarge
            
            Text {
                text: "Choose how long before your screen turns off"
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeBody
                font.family: Typography.fontFamily
                width: parent.width - Constants.spacingLarge * 2
                wrapMode: Text.WordWrap
            }
            
            Section {
                title: "Timeout Duration"
                width: parent.width - Constants.spacingLarge * 2
                
                Column {
                    width: parent.width
                    spacing: 0
                    
                    Repeater {
                        model: SettingsManagerCpp.screenTimeoutOptions()
                        
                        Rectangle {
                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"
                            
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: timeoutMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : 
                                       (DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Qt.rgba(20, 184, 166, 0.08) : "transparent")
                                border.width: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Constants.borderWidthMedium : 0
                                border.color: Colors.accent
                                
                                Behavior on color {
                                    ColorAnimation { duration: Constants.animationDurationFast }
                                }
                            }
                            
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Constants.spacingMedium
                                anchors.rightMargin: Constants.spacingMedium
                                spacing: Constants.spacingMedium
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeMedium
                                    height: Constants.iconSizeMedium
                                    radius: Constants.iconSizeMedium / 2
                                    color: "transparent"
                                    border.width: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? 
                                                  Math.round(6 * Constants.scaleFactor) : Constants.borderWidthMedium
                                    border.color: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? 
                                                  Colors.accent : Colors.border
                                    
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Constants.iconSizeSmall
                                        height: Constants.iconSizeSmall
                                        radius: Constants.iconSizeSmall / 2
                                        color: Colors.accent
                                        visible: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData)
                                    }
                                }
                                
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeBody
                                    font.family: Typography.fontFamily
                                    font.weight: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Font.DemiBold : Font.Normal
                                }
                            }
                            
                            MouseArea {
                                id: timeoutMouseArea
                                anchors.fill: parent
                                onClicked: {
                                    var value = SettingsManagerCpp.screenTimeoutValue(modelData)
                                    DisplayManager.setScreenTimeout(value)
                                    Logger.info("ScreenTimeoutPage", "Screen timeout changed to: " + modelData)
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

