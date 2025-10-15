import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Lists

MPage {
    id: aboutPage
    
    title: "About Device"
    showBackButton: true
    
    property string pageName: "about"
    
    signal navigateBack()
    
    onBackClicked: navigateBack()
    
    content: Column {
        width: parent.width
        spacing: MSpacing.xl
        topPadding: MSpacing.lg
        bottomPadding: MSpacing.lg
        
        MSection {
            title: "Device Information"
            width: parent.width
            anchors.leftMargin: MSpacing.lg
            anchors.rightMargin: MSpacing.lg
            
            MListItem {
                title: "Device Name"
                subtitle: SettingsManagerCpp.deviceName
                showRightIcon: true
                showDivider: true
            }
            
            MListItem {
                title: "Model"
                subtitle: "Marathon Passport"
                showRightIcon: false
                showDivider: true
            }
            
            MListItem {
                title: "OS Version"
                subtitle: "Marathon OS 1.0.0"
                showRightIcon: false
                showDivider: true
            }
            
            MListItem {
                title: "Build"
                subtitle: "Alpha"
                showRightIcon: false
                showDivider: true
            }
            
            MListItem {
                title: "Kernel Version"
                subtitle: Platform.os === "linux" ? "Linux 6.x" : "Darwin"
                showRightIcon: false
                showDivider: false
            }
        }
        
        MSection {
            title: "Hardware"
            width: parent.width
            anchors.leftMargin: MSpacing.lg
            anchors.rightMargin: MSpacing.lg
            
            MListItem {
                title: "Storage"
                subtitle: "64 GB"
                showRightIcon: false
                showDivider: true
            }
            
            MListItem {
                title: "Display"
                subtitle: DisplayManager.width + "x" + DisplayManager.height
                showRightIcon: false
                showDivider: true
            }
            
            MListItem {
                title: "Battery"
                subtitle: SystemStatusStore.batteryLevel + "%"
                showRightIcon: false
                showDivider: false
            }
        }
        
        MSection {
            title: "Legal"
            width: parent.width
            anchors.leftMargin: MSpacing.lg
            anchors.rightMargin: MSpacing.lg
            
            MListItem {
                title: "Open Source Licenses"
                showRightIcon: true
                showDivider: true
            }
            
            MListItem {
                title: "Terms of Service"
                showRightIcon: true
                showDivider: true
            }
            
            MListItem {
                title: "Privacy Policy"
                showRightIcon: true
                showDivider: false
            }
        }
    }
}

