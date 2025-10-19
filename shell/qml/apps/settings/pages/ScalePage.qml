import QtQuick
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: scalePage
    pageTitle: "UI Scale"
    
    property string pageName: "scale"
    
    content: Flickable {
        contentHeight: scaleContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: scaleContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: Constants.spacingLarge
            rightPadding: Constants.spacingLarge
            topPadding: Constants.spacingLarge
            
            Text {
                text: "Adjust the size of text and UI elements. Changes take effect immediately."
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeBody
                font.family: Typography.fontFamily
                wrapMode: Text.WordWrap
                width: parent.width - Constants.spacingLarge * 2
            }
            
            Section {
                title: "Scale Options"
                width: parent.width - Constants.spacingLarge * 2
                
                Column {
                    width: parent.width
                    spacing: Constants.spacingSmall
                    
                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 0.75 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 0.75 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: Constants.userScaleFactor === 0.75 ? Colors.accent : "transparent"
                                border.width: 2
                                border.color: Constants.userScaleFactor === 0.75 ? Colors.accent : Colors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Rectangle {
                                    visible: Constants.userScaleFactor === 0.75
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: Colors.backgroundDark
                                    anchors.centerIn: parent
                                }
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Text {
                                    text: "75% - Compact"
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: Typography.fontFamily
                                }
                                
                                Text {
                                    text: "More content, smaller text"
                                    color: Colors.textSecondary
                                    font.pixelSize: Typography.sizeSmall
                                    font.family: Typography.fontFamily
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 0.75
                                SettingsManagerCpp.userScaleFactor = 0.75
                            }
                        }
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 1.0 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 1.0 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: Constants.userScaleFactor === 1.0 ? Colors.accent : "transparent"
                                border.width: 2
                                border.color: Constants.userScaleFactor === 1.0 ? Colors.accent : Colors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Rectangle {
                                    visible: Constants.userScaleFactor === 1.0
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: Colors.backgroundDark
                                    anchors.centerIn: parent
                                }
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Text {
                                    text: "100% - Default"
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: Typography.fontFamily
                                }
                                
                                Text {
                                    text: "Recommended for most users"
                                    color: Colors.textSecondary
                                    font.pixelSize: Typography.sizeSmall
                                    font.family: Typography.fontFamily
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 1.0
                                SettingsManagerCpp.userScaleFactor = 1.0
                            }
                        }
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 1.25 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 1.25 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: Constants.userScaleFactor === 1.25 ? Colors.accent : "transparent"
                                border.width: 2
                                border.color: Constants.userScaleFactor === 1.25 ? Colors.accent : Colors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Rectangle {
                                    visible: Constants.userScaleFactor === 1.25
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: Colors.backgroundDark
                                    anchors.centerIn: parent
                                }
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Text {
                                    text: "125% - Comfortable"
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: Typography.fontFamily
                                }
                                
                                Text {
                                    text: "Larger text, easier to read"
                                    color: Colors.textSecondary
                                    font.pixelSize: Typography.sizeSmall
                                    font.family: Typography.fontFamily
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 1.25
                                SettingsManagerCpp.userScaleFactor = 1.25
                            }
                        }
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 1.5 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 1.5 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: Constants.userScaleFactor === 1.5 ? Colors.accent : "transparent"
                                border.width: 2
                                border.color: Constants.userScaleFactor === 1.5 ? Colors.accent : Colors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Rectangle {
                                    visible: Constants.userScaleFactor === 1.5
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: Colors.backgroundDark
                                    anchors.centerIn: parent
                                }
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Text {
                                    text: "150% - Large"
                                    color: Colors.text
                                    font.pixelSize: Typography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: Typography.fontFamily
                                }
                                
                                Text {
                                    text: "Maximum readability"
                                    color: Colors.textSecondary
                                    font.pixelSize: Typography.sizeSmall
                                    font.family: Typography.fontFamily
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 1.5
                                SettingsManagerCpp.userScaleFactor = 1.5
                            }
                        }
                    }
                }
            }
            
            Text {
                text: "Current: " + Math.round(Constants.scaleFactor * 100) + "% (Base: " + Math.round((Constants.screenHeight / Constants.baseHeight) * 100) + "% × User: " + Math.round(Constants.userScaleFactor * 100) + "%)"
                color: Colors.textTertiary
                font.pixelSize: Typography.sizeSmall
                font.family: Typography.fontFamily
                width: parent.width - Constants.spacingLarge * 2
                wrapMode: Text.WordWrap
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}
