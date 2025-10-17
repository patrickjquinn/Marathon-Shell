import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"

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
                            text: "12.5 GB used of 64 GB"
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
                                width: parent.width * 0.2
                                height: parent.height
                                radius: parent.radius
                                color: Qt.rgba(20, 184, 166, 0.8)
                            }
                        }
                    }
                }
            }
            
            Section {
                title: "Storage by Category"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Apps"
                    value: "4.2 GB"
                }
                
                SettingsListItem {
                    title: "Media"
                    value: "6.8 GB"
                }
                
                SettingsListItem {
                    title: "System"
                    value: "1.5 GB"
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

