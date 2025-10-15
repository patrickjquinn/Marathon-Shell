import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
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
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Brightness"
                width: parent.width - 48
                
                Column {
                    width: parent.width
                    spacing: Constants.spacingMedium
                    
                    Slider {
                        width: parent.width
                        from: 0
                        to: 1
                        value: SystemControlStore.brightness / 100.0
                        onMoved: {
                            SystemControlStore.setBrightness(value * 100)
                        }
                        
                        background: Rectangle {
                            x: parent.leftPadding
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: parent.availableWidth
                            height: 6
                            radius: 2
                            color: Qt.rgba(255, 255, 255, 0.1)
                            
                            Rectangle {
                                width: parent.width * parent.parent.value
                                height: parent.height
                                radius: parent.radius
                                color: Qt.rgba(20, 184, 166, 0.8)
                            }
                        }
                        
                        handle: Rectangle {
                            x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                            y: parent.topPadding + parent.availableHeight / 2 - height / 2
                            width: 24
                            height: 24
                            radius: 3
                            color: Qt.rgba(20, 184, 166, 0.9)
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.2)
                        }
                    }
                }
            }
            
            Section {
                title: "Display Settings"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Rotation Lock"
                    subtitle: "Lock screen orientation"
                    showToggle: true
                    toggleValue: SystemControlStore.isRotationLocked
                    onToggleChanged: {
                        SystemControlStore.toggleRotationLock()
                    }
                }
                
                SettingsListItem {
                    title: "Auto-Brightness"
                    subtitle: "Adjust brightness automatically"
                    showToggle: true
                    toggleValue: DisplayManager.autoBrightnessEnabled
                    onToggleChanged: (value) => {
                        DisplayManager.setAutoBrightness(value)
                    }
                }
                
                SettingsListItem {
                    title: "Screen Timeout"
                    value: DisplayManager.screenTimeoutString
                    showChevron: true
                    onSettingClicked: {
                        displayPage.parent.push(screenTimeoutPageComponent)
                    }
                }
            }
            
            Section {
                title: "Interface"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "UI Scale"
                    subtitle: Math.round(Constants.userScaleFactor * 100) + "%"
                    showChevron: true
                    onSettingClicked: {
                        displayPage.parent.push(scalePageComponent)
                    }
                }
                
                SettingsListItem {
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
}

