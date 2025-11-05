import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
    Flickable {
        anchors.fill: parent
        contentHeight: systemColumn.height
        clip: true
        
        Column {
            id: systemColumn
            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg
            
            Text {
                text: "⚙️ System Services"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Bold
                color: MColors.textPrimary
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "Power & Battery"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Column {
                        width: parent.width
                        spacing: MSpacing.xs
                        
                        Text {
                            text: "Battery: " + PowerManager.batteryLevel + "%"
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Charging: " + (PowerManager.isCharging ? "Yes" : "No")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Power Save: " + (PowerManager.isPowerSaveMode ? "On" : "Off")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Toggle Power Save"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                PowerManager.togglePowerSaveMode()
                                Logger.info("TestApp", "✓ Toggled power save mode")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "Network Status"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Column {
                        width: parent.width
                        spacing: MSpacing.xs
                        
                        Text {
                            text: "WiFi: " + (NetworkManager.wifiConnected ? ("Connected (" + NetworkManager.wifiSsid + ")") : "Disconnected")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Signal: " + NetworkManager.wifiSignalStrength + "%"
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                            visible: NetworkManager.wifiConnected
                        }
                        
                        Text {
                            text: "Cellular: " + (NetworkManager.cellularConnected ? NetworkManager.cellularOperator : "Disconnected")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Airplane Mode: " + (NetworkManager.airplaneModeEnabled ? "On" : "Off")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Scan WiFi"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NetworkManager.scanWifi()
                                Logger.info("TestApp", "✓ WiFi scan initiated")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Toggle Airplane"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NetworkManager.toggleAirplaneMode()
                                Logger.info("TestApp", "✓ Toggled airplane mode")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "Display"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Column {
                        width: parent.width
                        spacing: MSpacing.xs
                        
                        Text {
                            text: "Brightness: " + Math.round(DisplayManager.brightness * 100) + "%"
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Auto-brightness: " + (DisplayManager.autoBrightnessEnabled ? "On" : "Off")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Increase"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                DisplayManager.increaseBrightness()
                                Logger.info("TestApp", "✓ Increased brightness")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Decrease"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                DisplayManager.decreaseBrightness()
                                Logger.info("TestApp", "✓ Decreased brightness")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Toggle Auto"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                DisplayManager.setAutoBrightness(!DisplayManager.autoBrightnessEnabled)
                                Logger.info("TestApp", "✓ Toggled auto-brightness")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "Screenshot Service"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Take Screenshot"
                            variant: "secondary"
                            onClicked: {
                                HapticService.medium()
                                ScreenshotService.takeScreenshot()
                                Logger.info("TestApp", "✓ Screenshot taken")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
        }
    }
}

