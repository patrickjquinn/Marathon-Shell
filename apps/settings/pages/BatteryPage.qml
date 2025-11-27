import QtQuick
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Theme
import "../components"

SettingsPageTemplate {
    id: batteryPage
    pageTitle: "Battery"
    
    property string pageName: "battery"
    
    content: Flickable {
        contentHeight: batteryContent.height + 40
        clip: true
        
        Column {
            id: batteryContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            // Battery Status Header
            Column {
                width: parent.width
                spacing: MSpacing.sm
                
                Text {
                    text: PowerManagerService.batteryLevel + "%"
                    font.pixelSize: 48
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: PowerManagerService.isPowerSaveMode ? MColors.warning : MColors.textPrimary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: {
                        if (PowerManagerService.isCharging) return "Charging"
                        if (PowerManagerService.isPluggedIn) return "Plugged In, Not Charging"
                        
                        var time = PowerManagerService.estimatedBatteryTime
                        if (time > 0) {
                            var hours = Math.floor(time / 3600)
                            var minutes = Math.floor((time % 3600) / 60)
                            if (hours > 0) return hours + "h " + minutes + "m remaining"
                            return minutes + "m remaining"
                        }
                        return "Discharging"
                    }
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
            
            MSection {
                title: "Power Saver"
                width: parent.width - 48
                
                MSettingsListItem {
                    title: "Power Saver Mode"
                    subtitle: "Reduce performance to save battery"
                    showToggle: true
                    toggleValue: PowerManagerService.isPowerSaveMode
                    onToggleChanged: (value) => {
                        PowerManagerService.setPowerSaveMode(value)
                    }
                }
            }
            
            MSection {
                title: "Power Profile"
                subtitle: PowerManagerService.powerProfilesSupported ? "Optimize performance or battery life" : "Not supported on this device"
                width: parent.width - 48
                visible: PowerManagerService.powerProfilesSupported
                
                Column {
                    width: parent.width
                    spacing: 0
                    
                    MSettingsListItem {
                        title: "Performance"
                        subtitle: "Maximum performance, higher battery usage"
                        showToggle: false
                        value: (PowerManagerService.powerProfile === "performance") ? "✓" : ""
                        onSettingClicked: {
                            PowerManagerService.setPowerProfile("performance")
                            HapticService.light()
                        }
                    }
                    
                    MSettingsListItem {
                        title: "Balanced"
                        subtitle: "Balance between performance and battery"
                        showToggle: false
                        value: (PowerManagerService.powerProfile === "balanced") ? "✓" : ""
                        onSettingClicked: {
                            PowerManagerService.setPowerProfile("balanced")
                            HapticService.light()
                        }
                    }
                    
                    MSettingsListItem {
                        title: "Power Saver"
                        subtitle: "Optimize for battery life"
                        showToggle: false
                        value: (PowerManagerService.powerProfile === "power-saver") ? "✓" : ""
                        onSettingClicked: {
                            PowerManagerService.setPowerProfile("power-saver")
                            HapticService.light()
                        }
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}
