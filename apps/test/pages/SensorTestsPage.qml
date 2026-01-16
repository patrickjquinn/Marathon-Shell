import MarathonApp.Test
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

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
                            text: "Available: " + (SensorService.available ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Light Level: " + SensorService.ambientLight + " lux"
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
                                Logger.info("TestApp", "Enabled ambient light sensor (noop)");
                            }
                        }

                        MButton {
                            text: "Disable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                Logger.info("TestApp", "Disabled ambient light sensor (noop)");
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
                            text: "Available: " + (SensorService.available ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Near: " + (SensorService.proximityNear ? "Yes" : "No")
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
                                Logger.info("TestApp", "Enabled proximity sensor (noop)");
                            }
                        }

                        MButton {
                            text: "Disable"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                Logger.info("TestApp", "Disabled proximity sensor (noop)");
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
                            text: "Active: " + (LocationService.active ? "Yes" : "No")
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
                            text: "Start"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                LocationService.start();
                                Logger.info("TestApp", "Enabled location service");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Stop"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                LocationService.stop();
                                Logger.info("TestApp", "Stopped location service");
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
                        text: "Status: " + (((typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.enabled : false) ? "On" : "Off")
                        variant: "secondary"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Toggle"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                if (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp)
                                    FlashlightManagerCpp.toggle();

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
