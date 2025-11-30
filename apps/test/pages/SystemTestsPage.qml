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

            Row {
                spacing: MSpacing.sm
                Icon {
                    name: "cpu"
                    size: 24
                    color: MColors.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                MLabel {
                    text: "System Services"
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
                        text: "Power & Battery"
                        variant: "title"
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.xs

                        MLabel {
                            text: "Battery: " + PowerManager.batteryLevel + "%"
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Charging: " + (PowerManager.isCharging ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Power Save: " + (PowerManager.isPowerSaveMode ? "On" : "Off")
                            variant: "secondary"
                        }
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Toggle Power Save"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                PowerManager.togglePowerSaveMode();
                                Logger.info("TestApp", "Toggled power save mode");
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
                        text: "Network Status"
                        variant: "title"
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.xs

                        MLabel {
                            text: "WiFi: " + (NetworkManager.wifiConnected ? ("Connected (" + NetworkManager.wifiSsid + ")") : "Disconnected")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Signal: " + NetworkManager.wifiSignalStrength + "%"
                            variant: "secondary"
                            visible: NetworkManager.wifiConnected
                        }

                        MLabel {
                            text: "Cellular: " + (NetworkManager.cellularConnected ? NetworkManager.cellularOperator : "Disconnected")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Airplane Mode: " + (NetworkManager.airplaneModeEnabled ? "On" : "Off")
                            variant: "secondary"
                        }
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Scan WiFi"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                NetworkManager.scanWifi();
                                Logger.info("TestApp", "WiFi scan initiated");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Toggle Airplane"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                NetworkManager.toggleAirplaneMode();
                                Logger.info("TestApp", "Toggled airplane mode");
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
                        text: "Display"
                        variant: "title"
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.xs

                        MLabel {
                            text: "Brightness: " + Math.round(DisplayManager.brightness * 100) + "%"
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Auto-brightness: " + (DisplayManager.autoBrightnessEnabled ? "On" : "Off")
                            variant: "secondary"
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Increase"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                DisplayManager.increaseBrightness();
                                Logger.info("TestApp", "Increased brightness");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Decrease"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                DisplayManager.decreaseBrightness();
                                Logger.info("TestApp", "Decreased brightness");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Toggle Auto"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                DisplayManager.setAutoBrightness(!DisplayManager.autoBrightnessEnabled);
                                Logger.info("TestApp", "Toggled auto-brightness");
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
                        text: "Screenshot Service"
                        variant: "title"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Take Screenshot"
                            variant: "accent"
                            onClicked: {
                                HapticService.medium();
                                ScreenshotService.takeScreenshot();
                                Logger.info("TestApp", "Screenshot taken");
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
