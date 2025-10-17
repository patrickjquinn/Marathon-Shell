import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: aboutPage
    pageTitle: "About Device"
    
    property string pageName: "about"
    
    content: Flickable {
        contentHeight: aboutContent.height + 40
        clip: true
        
        Column {
            id: aboutContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Device Information"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Device Name"
                    value: SettingsManagerCpp.deviceName
                    showChevron: true
                }
                
                SettingsListItem {
                    title: "Model"
                    value: "Marathon Passport"
                }
                
                SettingsListItem {
                    title: "OS Version"
                    value: "Marathon OS 1.0.0"
                }
                
                SettingsListItem {
                    title: "Build"
                    value: "Alpha"
                }
                
                SettingsListItem {
                    title: "Kernel Version"
                    value: Platform.os === "linux" ? "Linux 6.x" : "Darwin"
                }
            }
            
            Section {
                title: "Hardware"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Storage"
                    value: "64 GB"
                }
                
                SettingsListItem {
                    title: "Display"
                    value: DisplayManager.width + "x" + DisplayManager.height
                }
                
                SettingsListItem {
                    title: "Battery"
                    value: SystemStatusStore.batteryLevel + "%"
                }
            }
            
            Section {
                title: "Legal"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Open Source Licenses"
                    showChevron: true
                }
                
                SettingsListItem {
                    title: "Terms of Service"
                    showChevron: true
                }
                
                SettingsListItem {
                    title: "Privacy Policy"
                    showChevron: true
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

