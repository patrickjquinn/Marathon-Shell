import MarathonApp.Test
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

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
                            text: "Battery: " + ((typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.batteryLevel : 0) + "%"
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Charging: " + (((typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.isCharging : false) ? "Yes" : "No")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Power Save: " + (((typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.isPowerSaveMode : false) ? "On" : "Off")
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
                                if (typeof PowerManagerService !== "undefined" && PowerManagerService)
                                    PowerManagerService.setPowerSaveMode(!PowerManagerService.isPowerSaveMode);

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
                            text: "WiFi: " + ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiConnected) ? ("Connected (" + NetworkManagerCpp.wifiSsid + ")") : "Disconnected")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Signal: " + ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiSignalStrength : 0) + "%"
                            variant: "secondary"
                            visible: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiConnected
                        }

                        MLabel {
                            text: "Cellular: " + ((typeof ModemManagerCpp !== "undefined" && ModemManagerCpp && ModemManagerCpp.registered) ? ModemManagerCpp.operatorName : "Disconnected")
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Airplane Mode: " + ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.airplaneModeEnabled) ? "On" : "Off")
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
                                if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                                    NetworkManagerCpp.scanWifi();

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
                                if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                                    NetworkManagerCpp.setAirplaneMode(!NetworkManagerCpp.airplaneModeEnabled);

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
                            text: "Brightness: " + ((typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? Math.round(DisplayManagerCpp.brightness * 100) : 0) + "%"
                            variant: "secondary"
                        }

                        MLabel {
                            text: "Auto-brightness: " + (((typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.autoBrightnessEnabled : false) ? "On" : "Off")
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
                                if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                                    DisplayManagerCpp.brightness = Math.min(1, DisplayManagerCpp.brightness + 0.1);

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
                                if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                                    DisplayManagerCpp.brightness = Math.max(0, DisplayManagerCpp.brightness - 0.1);

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
                                if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                                    DisplayPolicyControllerCpp.autoBrightnessEnabled = !DisplayPolicyControllerCpp.autoBrightnessEnabled;

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
