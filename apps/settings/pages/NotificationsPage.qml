pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: notificationsPage

    property string pageName: "notifications"

    pageTitle: "Notifications"

    content: Flickable {
        contentHeight: notificationsContent.height + 40
        clip: true

        Column {
            id: notificationsContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Notification Settings"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Do Not Disturb"
                    subtitle: "Silence notifications and calls"
                    showToggle: true
                    toggleValue: SystemControlStore.isDndMode
                    onToggleChanged: {
                        SystemControlStore.toggleDndMode();
                    }
                }

                MSettingsListItem {
                    title: "Show on Lock Screen"
                    subtitle: "Display notifications when locked"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.showNotificationsOnLockScreen
                    onToggleChanged: value => {
                        SettingsManagerCpp.showNotificationsOnLockScreen = value;
                    }
                }

                MSettingsListItem {
                    title: "Notification Sound"
                    value: SettingsManagerCpp.formatSoundName(SettingsManagerCpp.notificationSound)
                    showChevron: true
                    onSettingClicked: SettingsController.requestPage("sound")
                }
            }

            MSection {
                title: "Per-App Notifications"
                width: parent.width - 48

                Repeater {
                    model: SettingsController.notificationApps || []

                    MSettingsListItem {
                        required property var modelData

                        title: modelData.name
                        subtitle: modelData.id
                        iconName: "app-window"
                        showToggle: true
                        toggleValue: modelData.enabled
                        onToggleChanged: value => {
                            SettingsController.setNotificationEnabled(modelData.id, value);
                        }
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
