import QtQuick
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: notificationsPage
    pageTitle: "Notifications"
    
    property string pageName: "notifications"
    
    content: Flickable {
        contentHeight: notificationsContent.height + 40
        clip: true
        
        Column {
            id: notificationsContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Notification Settings"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Do Not Disturb"
                    subtitle: "Silence notifications and calls"
                    showToggle: true
                    toggleValue: SystemControlStore.isDndMode
                    onToggleChanged: {
                        SystemControlStore.toggleDndMode()
                    }
                }
                
                SettingsListItem {
                    title: "Show on Lock Screen"
                    subtitle: "Display notifications when locked"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.showNotificationsOnLockScreen
                    onToggleChanged: (value) => {
                        SettingsManagerCpp.showNotificationsOnLockScreen = value
                    }
                }
                
                SettingsListItem {
                    title: "Notification Sound"
                    value: AudioManager.currentNotificationSoundName
                    showChevron: true
                }
            }
            
            Section {
                title: "Per-App Notifications"
                subtitle: "Coming soon"
                width: parent.width - 48
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

