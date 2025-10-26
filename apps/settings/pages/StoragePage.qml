import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "components"

SettingsPageTemplate {
    id: storagePage
    pageTitle: "Storage"
    
    property string pageName: "storage"
    
    content: Flickable {
        contentHeight: storageContent.height + 40
        clip: true
        
        Column {
            id: storageContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Storage Overview"
                width: parent.width - 48
                
                Rectangle {
                    width: parent.width
                    height: Constants.bottomBarHeight
                    radius: 4
                    color: Qt.rgba(255, 255, 255, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.08)
                    
                    Column {
                        anchors.centerIn: parent
                        spacing: Constants.spacingSmall
                        
                        Text {
                            text: StorageManager.usedSpaceString + " used of " + StorageManager.totalSpaceString
                            color: Colors.text
                            font.pixelSize: Typography.sizeLarge
                            font.weight: Font.Bold
                            font.family: Typography.fontFamily
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        
                        Rectangle {
                            width: 200
                            height: 8
                            radius: 4
                            color: Qt.rgba(255, 255, 255, 0.1)
                            anchors.horizontalCenter: parent.horizontalCenter
                            
                            Rectangle {
                                width: parent.width * StorageManager.usedPercentage
                                height: parent.height
                                radius: parent.radius
                                color: {
                                    if (StorageManager.usedPercentage > 0.9) return Qt.rgba(255, 59, 48, 0.8)      // Red when >90%
                                    if (StorageManager.usedPercentage > 0.75) return Qt.rgba(255, 149, 0, 0.8)    // Orange when >75%
                                    return Qt.rgba(20, 184, 166, 0.8)  // Teal when <75%
                                }
                            }
                        }
                    }
                }
            }
            
            Section {
                title: "Storage Details"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Used"
                    value: StorageManager.usedSpaceString
                }
                
                SettingsListItem {
                    title: "Available"
                    value: StorageManager.availableSpaceString
                }
                
                SettingsListItem {
                    title: "Total Capacity"
                    value: StorageManager.totalSpaceString
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

