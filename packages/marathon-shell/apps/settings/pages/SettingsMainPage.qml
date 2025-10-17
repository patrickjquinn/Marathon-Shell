import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Page {
    id: mainPage
    
    property string pageName: "main"
    
    signal navigateToPage(string page)
    signal requestClose()
    
    background: Rectangle {
        color: Colors.backgroundDark
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
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24
            
            // Page title
            Text {
                text: "Settings"
                color: Colors.text
                font.pixelSize: Typography.sizeXLarge
                font.weight: Font.Bold
                font.family: Typography.fontFamily
            }
            
            // Network & Connectivity
            Section {
                title: "Network & Connectivity"
                subtitle: "Manage your network connections"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "WiFi"
                    subtitle: SystemStatusStore.wifiConnected ? ("Connected" + (SystemStatusStore.wifiNetwork ? " • " + SystemStatusStore.wifiNetwork : "")) : "Not connected"
                    iconName: "wifi"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("wifi")
                    }
                }
                
                SettingsListItem {
                    title: "Bluetooth"
                    subtitle: SystemControlStore.isBluetoothOn ? "On" : "Off"
                    iconName: "bluetooth"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("bluetooth")
                    }
                }
                
                SettingsListItem {
                    title: "Mobile Network"
                    subtitle: "Manage cellular data"
                    iconName: "signal"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("cellular")
                    }
                }
                
                SettingsListItem {
                    title: "Airplane Mode"
                    subtitle: "Turn off all wireless connections"
                    iconName: "plane"
                    showToggle: true
                    toggleValue: SystemControlStore.isAirplaneModeOn
                    onToggleChanged: (value) => {
                        SystemControlStore.toggleAirplaneMode()
                    }
                }
            }
            
            // Display & Brightness
            Section {
                title: "Display & Brightness"
                subtitle: "Customize your screen settings"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Display Settings"
                    subtitle: "Brightness, rotation, and screen timeout"
                    iconName: "sun"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("display")
                    }
                }
            }
            
            // Sound & Notifications
            Section {
                title: "Sound & Notifications"
                subtitle: "Manage audio and notification settings"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Sound Settings"
                    subtitle: "Volume, ringtones, and notification sounds"
                    iconName: "volume-2"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("sound")
                    }
                }
                
                SettingsListItem {
                    title: "Notifications"
                    subtitle: "Manage app notifications"
                    iconName: "bell"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("notifications")
                    }
                }
                
                SettingsListItem {
                    title: "Do Not Disturb"
                    subtitle: "Silence notifications and calls"
                    iconName: "moon"
                    showToggle: true
                    toggleValue: SystemControlStore.isDndMode
                    onToggleChanged: (value) => {
                        SystemControlStore.toggleDndMode()
                    }
                }
            }
            
            // Storage & Battery
            Section {
                title: "Storage & Battery"
                subtitle: "Manage device resources"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Storage"
                    subtitle: "Manage storage and apps"
                    iconName: "hard-drive"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("storage")
                    }
                }
                
                SettingsListItem {
                    title: "Battery Saver"
                    subtitle: "Extend battery life"
                    iconName: "battery"
                    showToggle: true
                    toggleValue: SystemControlStore.isLowPowerMode
                    onToggleChanged: (value) => {
                        SystemControlStore.toggleLowPowerMode()
                    }
                }
            }
            
            // System
            Section {
                title: "System"
                subtitle: "Device information and preferences"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "App Manager"
                    subtitle: "Install and manage applications"
                    iconName: "package"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("appmanager")
                    }
                }
                
                SettingsListItem {
                    title: "About Device"
                    subtitle: "Device name, OS version, and information"
                    iconName: "info"
                    showChevron: true
                    onSettingClicked: {
                        mainPage.navigateToPage("about")
                    }
                }
            }
            
            Item { height: 40 }
        }
    }
    
    // Swipe down to close gesture (BB10 style)
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        z: -1
        
        property real startY: 0
        property bool isDragging: false
        
        onPressed: (mouse) => {
            if (scrollView.contentY <= 0) {
                startY = mouse.y
                isDragging = false
            }
        }
        
        onPositionChanged: (mouse) => {
            if (scrollView.contentY <= 0) {
                var deltaY = mouse.y - startY
                if (deltaY > 10) {
                    isDragging = true
                }
                
                if (isDragging && deltaY > 100) {
                    mainPage.requestClose()
                    isDragging = false
                }
            }
        }
        
        onReleased: {
            isDragging = false
        }
    }
    
    Component.onCompleted: {
        Logger.info("SettingsMainPage", "Initialized")
    }
}

