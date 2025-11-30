import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers

Page {
    id: mainPage

    property string pageName: "main"

    signal navigateToPage(string page)
    signal requestClose

    background: Rectangle {
        color: MColors.background
    }

    Flickable {
        id: scrollView
        anchors.fill: parent
        contentHeight: settingsContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 1500
        maximumFlickVelocity: 2500

        Column {
            id: settingsContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24

            // Page title
            Text {
                text: "Settings"
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeXLarge
                font.weight: Font.Bold
                font.family: MTypography.fontFamily
            }

            // Network & Connectivity
            MSection {
                title: "Network & Connectivity"
                subtitle: "Manage your network connections"
                width: parent.width - 48

                MSettingsListItem {
                    title: "WiFi"
                    subtitle: SystemStatusStore.wifiConnected ? ("Connected" + (SystemStatusStore.wifiNetwork ? " • " + SystemStatusStore.wifiNetwork : "")) : "Not connected"
                    iconName: "wifi"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("wifi");
                    }
                }

                MSettingsListItem {
                    title: "Bluetooth"
                    subtitle: SystemControlStore.isBluetoothOn ? "On" : "Off"
                    iconName: "bluetooth"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("bluetooth");
                    }
                }

                MSettingsListItem {
                    title: "Mobile Network"
                    subtitle: "Manage cellular data"
                    iconName: "signal"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("cellular");
                    }
                }

                MSettingsListItem {
                    title: "Airplane Mode"
                    subtitle: "Turn off all wireless connections"
                    iconName: "plane"
                    showToggle: true
                    toggleValue: SystemControlStore.isAirplaneModeOn
                    onToggleChanged: value => {
                        SystemControlStore.toggleAirplaneMode();
                    }
                }
            }

            // Display & Brightness
            MSection {
                title: "Display & Brightness"
                subtitle: "Customize your screen settings"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Display Settings"
                    subtitle: "Brightness, rotation, and screen timeout"
                    iconName: "sun"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("display");
                    }
                }
            }

            // Sound & Notifications
            MSection {
                title: "Sound & Notifications"
                subtitle: "Manage audio and notification settings"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Sound Settings"
                    subtitle: "Volume, ringtones, and notification sounds"
                    iconName: "volume-2"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("sound");
                    }
                }

                MSettingsListItem {
                    title: "Notifications"
                    subtitle: "Manage app notifications"
                    iconName: "bell"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("notifications");
                    }
                }

                MSettingsListItem {
                    title: "Do Not Disturb"
                    subtitle: "Silence notifications and calls"
                    iconName: "moon"
                    showToggle: true
                    toggleValue: SystemControlStore.isDndMode
                    onToggleChanged: value => {
                        SystemControlStore.toggleDndMode();
                    }
                }
            }

            // Storage & Battery
            MSection {
                title: "Storage & Battery"
                subtitle: "Manage device resources"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Storage"
                    subtitle: "Manage storage and apps"
                    iconName: "hard-drive"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("storage");
                    }
                }

                MSettingsListItem {
                    title: "Battery"
                    subtitle: "Power saver, battery usage, and profiles"
                    iconName: "battery"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("battery");
                    }
                }
            }

            // System
            MSection {
                title: "System"
                subtitle: "Device information and preferences"
                width: parent.width - 48

                MSettingsListItem {
                    title: "App Manager"
                    subtitle: "Install and manage applications"
                    iconName: "package"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("appmanager");
                    }
                }

                MSettingsListItem {
                    title: "About Device"
                    subtitle: "Device name, OS version, and information"
                    iconName: "info"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("about");
                    }
                }
            }

            // Security & Privacy
            MSection {
                title: "Security & Privacy"
                subtitle: "Lock screen, authentication, and security"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Security"
                    subtitle: "Lock screen, PIN, fingerprint, and authentication"
                    iconName: "shield"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("security");
                    }
                }
            }

            // Apps & Filters
            MSection {
                title: "Customization"
                subtitle: "Personalize your Marathon experience"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Quick Settings"
                    subtitle: "Customize Quick Settings tiles"
                    iconName: "sliders"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("quicksettings");
                    }
                }
            }

            MSection {
                title: "Apps & Filters"
                subtitle: "Control which apps are displayed"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Hidden Apps"
                    subtitle: SettingsManagerCpp.hiddenApps.length + " app(s) hidden"
                    iconName: "eye-off"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("hiddenapps");
                    }
                }

                MSettingsListItem {
                    title: "Default Apps"
                    subtitle: "Choose apps for specific actions"
                    iconName: "star"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("defaultapps");
                    }
                }

                MSettingsListItem {
                    title: "App Sorting & Layout"
                    subtitle: {
                        var sortText = SettingsManagerCpp.appSortOrder === "alphabetical" ? "Alphabetical" : SettingsManagerCpp.appSortOrder === "frequent" ? "Most Used" : SettingsManagerCpp.appSortOrder === "recent" ? "Recently Added" : "Custom";
                        var gridText = SettingsManagerCpp.appGridColumns === 0 ? "Auto" : SettingsManagerCpp.appGridColumns + " columns";
                        return sortText + " • " + gridText;
                    }
                    iconName: "layout"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("appsort");
                    }
                }

                MSettingsListItem {
                    title: "Filter Non-Mobile Apps"
                    subtitle: "Only show apps optimized for mobile screens"
                    iconName: "smartphone"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.filterMobileFriendlyApps
                    onToggleChanged: value => {
                        SettingsManagerCpp.filterMobileFriendlyApps = value;
                        Logger.info("Settings", "Mobile app filter: " + value + " (restart required)");
                    }
                }

                MSettingsListItem {
                    title: "Search Native Apps"
                    subtitle: "Include system apps in search results"
                    iconName: "search"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.searchNativeApps
                    onToggleChanged: value => {
                        SettingsManagerCpp.searchNativeApps = value;
                        Logger.info("Settings", "Search native apps: " + value);
                    }
                }

                MSettingsListItem {
                    title: "Show Notification Badges"
                    subtitle: "Display unread counts on app icons"
                    iconName: "bell-ring"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.showNotificationBadges
                    onToggleChanged: value => {
                        SettingsManagerCpp.showNotificationBadges = value;
                        Logger.info("Settings", "Notification badges: " + value);
                    }
                }

                MSettingsListItem {
                    title: "Show Frequent Apps"
                    subtitle: "Display most used apps at the top"
                    iconName: "trending-up"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.showFrequentApps
                    onToggleChanged: value => {
                        SettingsManagerCpp.showFrequentApps = value;
                        Logger.info("Settings", "Show frequent apps: " + value);
                    }
                }
            }

            Item {
                height: 40
            }
        }
    }

    // Swipe down to close gesture (BB10 style)
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        z: -1

        property real startY: 0
        property bool isDragging: false

        onPressed: mouse => {
            if (scrollView.contentY <= 0) {
                startY = mouse.y;
                isDragging = false;
            }
        }

        onPositionChanged: mouse => {
            if (scrollView.contentY <= 0) {
                var deltaY = mouse.y - startY;
                if (deltaY > 10) {
                    isDragging = true;
                }

                if (isDragging && deltaY > 100) {
                    mainPage.requestClose();
                    isDragging = false;
                }
            }
        }

        onReleased: {
            isDragging = false;
        }
    }

    Component.onCompleted: {
        Logger.info("SettingsMainPage", "Initialized");
    }
}
