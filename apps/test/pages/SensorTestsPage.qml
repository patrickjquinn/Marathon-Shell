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

            Row {
                spacing: MSpacing.sm
                Icon {
                    name: "activity"
                    size: 24
                    color: MColors.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                MLabel {
                    text: "Sensors"
                    variant: "headline"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MCard {
                width: parent.width - parent.padding * 2

                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg

                    MLabel {
                        text: "Ambient Light Sensor"
                        variant: "title"
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.xs

                        MLabel {
                            text: "Available: " + (AmbientLightSensor.available ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Light Level: " + AmbientLightSensor.lightLevel + " lux"
                            variant: "secondary"
                        }
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Enable"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                AmbientLightSensor.enable();
                                Logger.info("TestApp", "Enabled ambient light sensor");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Disable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                AmbientLightSensor.disable();
                                Logger.info("TestApp", "Disabled ambient light sensor");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
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

                    MLabel {
                        text: "Proximity Sensor"
                        variant: "title"
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.xs

                        MLabel {
                            text: "Available: " + (ProximitySensor.available ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Near: " + (ProximitySensor.near ? "Yes" : "No")
                            variant: "secondary"
                        }
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Enable"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                ProximitySensor.enable();
                                Logger.info("TestApp", "Enabled proximity sensor");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Disable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                ProximitySensor.disable();
                                Logger.info("TestApp", "Disabled proximity sensor");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
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

                    MLabel {
                        text: "Location Service"
                        variant: "title"
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.xs

                        MLabel {
                            text: "Enabled: " + (LocationService.enabled ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Lat: " + LocationService.latitude.toFixed(6)
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Lon: " + LocationService.longitude.toFixed(6)
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Accuracy: " + LocationService.accuracy + "m"
                            variant: "secondary"
                        }
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Enable"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                LocationService.enable();
                                Logger.info("TestApp", "Enabled location service");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Get Location"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                LocationService.startUpdating();
                                Logger.info("TestApp", "Requested location update");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
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

                    MLabel {
                        text: "Flashlight"
                        variant: "title"
                    }

                    MLabel {
                        text: "Status: " + (FlashlightManager.enabled ? "On" : "Off")
                        variant: "secondary"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Toggle"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                FlashlightManager.toggle();
                                Logger.info("TestApp", "Toggled flashlight");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
