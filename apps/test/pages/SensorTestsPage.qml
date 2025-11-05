import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
    Flickable {
        anchors.fill: parent
        contentHeight: sensorColumn.height
        clip: true
        
        Column {
            id: sensorColumn
            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg
            
            Text {
                text: "📡 Sensors"
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
                        text: "Ambient Light Sensor"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Column {
                        width: parent.width
                        spacing: MSpacing.xs
                        
                        Text {
                            text: "Available: " + (AmbientLightSensor.available ? "Yes" : "No")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Light Level: " + AmbientLightSensor.lightLevel + " lux"
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Enable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AmbientLightSensor.enable()
                                Logger.info("TestApp", "✓ Enabled ambient light sensor")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Disable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AmbientLightSensor.disable()
                                Logger.info("TestApp", "✓ Disabled ambient light sensor")
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
                        text: "Proximity Sensor"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Column {
                        width: parent.width
                        spacing: MSpacing.xs
                        
                        Text {
                            text: "Available: " + (ProximitySensor.available ? "Yes" : "No")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Near: " + (ProximitySensor.near ? "Yes" : "No")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Enable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                ProximitySensor.enable()
                                Logger.info("TestApp", "✓ Enabled proximity sensor")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Disable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                ProximitySensor.disable()
                                Logger.info("TestApp", "✓ Disabled proximity sensor")
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
                        text: "Location Service"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Column {
                        width: parent.width
                        spacing: MSpacing.xs
                        
                        Text {
                            text: "Enabled: " + (LocationService.enabled ? "Yes" : "No")
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Lat: " + LocationService.latitude.toFixed(6)
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Lon: " + LocationService.longitude.toFixed(6)
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "Accuracy: " + LocationService.accuracy + "m"
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Enable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                LocationService.enable()
                                Logger.info("TestApp", "✓ Enabled location service")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Get Location"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                LocationService.updateLocation()
                                Logger.info("TestApp", "✓ Requested location update")
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
                        text: "Flashlight"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Status: " + (FlashlightManager.enabled ? "On" : "Off")
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Toggle"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                FlashlightManager.toggle()
                                Logger.info("TestApp", "✓ Toggled flashlight")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
        }
    }
}

