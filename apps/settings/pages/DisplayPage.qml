import QtQuick
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Theme
import "../components"

SettingsPageTemplate {
    id: displayPage
    pageTitle: "Display & Brightness"
    
    property string pageName: "display"
    
    content: Flickable {
        contentHeight: displayContent.height + 40
        clip: true
        
        Column {
            id: displayContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            MSection {
                title: "Power Profile"
                subtitle: PowerManagerCpp.powerProfilesSupported ? "Optimize performance or battery life" : "Not supported on this device"
                width: parent.width - 48
                visible: PowerManagerCpp.powerProfilesSupported
                
                Column {
                    width: parent.width
                    spacing: MSpacing.sm
                    
                    MSettingsListItem {
                        title: "Performance"
                        subtitle: "Maximum performance, higher battery usage"
                        showToggle: false
                        onSettingClicked: {
                            PowerManagerCpp.setPowerProfile("performance")
                        }
                    }
                    
                    MSettingsListItem {
                        title: "Balanced"
                        subtitle: "Balance between performance and battery"
                        showToggle: false
                        onSettingClicked: {
                            PowerManagerCpp.setPowerProfile("balanced")
                        }
                    }
                    
                    MSettingsListItem {
                        title: "Power Saver"
                        subtitle: "Optimize for battery life"
                        showToggle: false
                        onSettingClicked: {
                            PowerManagerCpp.setPowerProfile("power-saver")
                        }
                    }
                }
            }
            
            MSection {
                title: "Brightness"
                width: parent.width - 48
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    
                    MSlider {
                        width: parent.width
                        from: 0
                        to: 100
                        value: SystemControlStore.brightness
                        onValueChanged: {
                            if (pressed) {
                                SystemControlStore.setBrightness(value)
                            }
                        }
                    }
                }
            }
            
            MSection {
                title: "Display Settings"
                width: parent.width - 48
                
                MSettingsListItem {
                    title: "Rotation Lock"
                    subtitle: "Lock screen orientation"
                    showToggle: true
                    toggleValue: SystemControlStore.isRotationLocked
                    onToggleChanged: {
                        SystemControlStore.toggleRotationLock()
                    }
                }
                
                MSettingsListItem {
                    title: "Auto-Brightness"
                    subtitle: "Adjust brightness automatically"
                    showToggle: true
                    toggleValue: DisplayManager.autoBrightnessEnabled
                    onToggleChanged: (value) => {
                        DisplayManager.setAutoBrightness(value)
                    }
                }
                
                MSettingsListItem {
                    title: "Screen Timeout"
                    value: DisplayManager.screenTimeoutString
                    showChevron: true
                    onSettingClicked: {
                        displayPage.parent.push(screenTimeoutPageComponent)
                    }
                }
            }
            
            MSection {
                title: "Status Bar"
                width: parent.width - 48
                
                MSettingsListItem {
                    title: "Clock Position"
                    subtitle: "Choose where the clock appears"
                    value: {
                        var pos = SettingsManagerCpp.statusBarClockPosition || "center"
                        return pos.charAt(0).toUpperCase() + pos.slice(1)
                    }
                    showChevron: true
                    onSettingClicked: {
                        displayPage.parent.push(clockPositionPageComponent)
                    }
                }
            }
            
            MSection {
                title: "Interface"
                width: parent.width - 48
                
                MSettingsListItem {
                    title: "UI Scale"
                    subtitle: Math.round(Constants.userScaleFactor * 100) + "%"
                    showChevron: true
                    onSettingClicked: {
                        displayPage.parent.push(scalePageComponent)
                    }
                }
                
                MSettingsListItem {
                    title: "Wallpaper"
                    subtitle: "Change background image"
                    showChevron: true
                    onSettingClicked: {
                        displayPage.parent.push(wallpaperPageComponent)
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    Component {
        id: scalePageComponent
        ScalePage {
            onNavigateBack: displayPage.parent.pop()
        }
    }
    
    Component {
        id: wallpaperPageComponent
        WallpaperPage {
            onNavigateBack: displayPage.parent.pop()
        }
    }
    
    Component {
        id: screenTimeoutPageComponent
        ScreenTimeoutPage {
            onNavigateBack: displayPage.parent.pop()
        }
    }
    
    Component {
        id: clockPositionPageComponent
        SettingsPageTemplate {
            pageTitle: "Clock Position"
            
            content: Flickable {
                contentHeight: clockPositionContent.height + 40
                clip: true
                
                Column {
                    id: clockPositionContent
                    width: parent.width
                    spacing: MSpacing.xl
                    leftPadding: 24
                    rightPadding: 24
                    topPadding: 24
                    
                    MSection {
                        title: "Choose clock position"
                        subtitle: "Useful for devices with notches or punch-holes"
                        width: parent.width - 48
                        
                        Column {
                            width: parent.width
                            spacing: 0
                            
                            MSettingsListItem {
                                title: "Left"
                                subtitle: "Best for right-side notches"
                                value: (SettingsManagerCpp.statusBarClockPosition === "left") ? "✓" : ""
                                onSettingClicked: {
                                    SettingsManagerCpp.statusBarClockPosition = "left"
                                    HapticService.light()
                                }
                            }
                            
                            MSettingsListItem {
                                title: "Center"
                                subtitle: "Default position"
                                value: (!SettingsManagerCpp.statusBarClockPosition || SettingsManagerCpp.statusBarClockPosition === "center") ? "✓" : ""
                                onSettingClicked: {
                                    SettingsManagerCpp.statusBarClockPosition = "center"
                                    HapticService.light()
                                }
                            }
                            
                            MSettingsListItem {
                                title: "Right"
                                subtitle: "Best for left-side notches"
                                value: (SettingsManagerCpp.statusBarClockPosition === "right") ? "✓" : ""
                                onSettingClicked: {
                                    SettingsManagerCpp.statusBarClockPosition = "right"
                                    HapticService.light()
                                }
                            }
                        }
                    }
                    
                    Item { height: Constants.navBarHeight }
                }
            }
            
            onNavigateBack: displayPage.parent.pop()
        }
    }
}

