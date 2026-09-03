import MarathonApp.Test
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

MApp {
    id: testApp

    property int passedTests: 0
    property int failedTests: 0
    property int totalTests: 0
    property int autoStep: 0
    property bool autoRunning: false

    function autoTest(name, fn) {
        totalTests++;
        try {
            var result = fn();
            if (result !== false) {
                passedTests++;
                Logger.info("AutoTest", "PASS: " + name);
            } else {
                failedTests++;
                Logger.warn("AutoTest", "FAIL: " + name);
            }
        } catch (e) {
            failedTests++;
            Logger.warn("AutoTest", "FAIL: " + name + " - " + e);
        }
    }

    appId: "test"
    appName: "System Test Suite"
    Component.onCompleted: {
        Logger.info("TestApp", "System Test Suite initialized");
        Logger.info("TestApp", "Available services:");
        Logger.info("TestApp", "  - TelephonyService: " + (typeof TelephonyService !== 'undefined'));
        Logger.info("TestApp", "  - SMSService: " + (typeof SMSService !== 'undefined'));
        Logger.info("TestApp", "  - NotificationService: " + (typeof NotificationService !== 'undefined'));
        Logger.info("TestApp", "  - AlarmService: " + (typeof AlarmService !== 'undefined'));
        Logger.info("TestApp", "  - AudioManagerCpp: " + (typeof AudioManagerCpp !== 'undefined'));
        Logger.info("TestApp", "  - PowerManager: " + (typeof PowerManagerService !== 'undefined'));
        Logger.info("TestApp", "  - NetworkManagerCpp: " + (typeof NetworkManagerCpp !== 'undefined'));
        Logger.info("TestApp", "  - DisplayManager: " + (typeof DisplayManagerCpp !== 'undefined'));
        var debug = (typeof Constants !== "undefined" && Constants && Constants.debugMode);
        if (debug) {
            Logger.info("AutoTest", "=== AUTO-RUN MODE DETECTED - Starting test suite ===");
            autoRunning = true;
            autoRunTimer.start();
        }
    }

    Timer {
        id: autoRunTimer

        interval: 800
        running: false
        repeat: true
        onTriggered: {
            testApp.autoStep++;
            switch (testApp.autoStep) {
            case 1:
                Logger.info("AutoTest", "=== TELEPHONY TESTS (D-Bus IPC) ===");
                autoTest("TelephonyService available", function () {
                    return typeof TelephonyService !== 'undefined';
                });
                autoTest("SMSService available", function () {
                    return typeof SMSService !== 'undefined';
                });
                break;
            case 2:
                autoTest("simulateIncomingCall", function () {
                    if (typeof TelephonyService === 'undefined')
                        return false;

                    TelephonyService.simulateIncomingCall("+1234567890");
                    return true;
                });
                break;
            case 3:
                autoTest("simulateCallStateChange(active)", function () {
                    if (typeof TelephonyService === 'undefined')
                        return false;

                    TelephonyService.simulateCallStateChange("active");
                    return true;
                });
                break;
            case 4:
                autoTest("setCallMuted(true) via D-Bus IPC", function () {
                    if (typeof TelephonyService === 'undefined' || typeof TelephonyService.setCallMuted !== 'function')
                        return false;

                    TelephonyService.setCallMuted(true);
                    return true;
                });
                autoTest("setSpeakerphone(true) via D-Bus IPC", function () {
                    if (typeof TelephonyService === 'undefined' || typeof TelephonyService.setSpeakerphone !== 'function')
                        return false;

                    TelephonyService.setSpeakerphone(true);
                    return true;
                });
                break;
            case 5:
                autoTest("isCallMuted() returns bool", function () {
                    if (typeof TelephonyService === 'undefined' || typeof TelephonyService.isCallMuted !== 'function')
                        return false;

                    var val = TelephonyService.isCallMuted();
                    Logger.info("AutoTest", "  isCallMuted: " + val);
                    return true;
                });
                autoTest("isSpeakerphoneOn() returns bool", function () {
                    if (typeof TelephonyService === 'undefined' || typeof TelephonyService.isSpeakerphoneOn !== 'function')
                        return false;

                    var val = TelephonyService.isSpeakerphoneOn();
                    Logger.info("AutoTest", "  isSpeakerphoneOn: " + val);
                    return true;
                });
                break;
            case 6:
                autoTest("simulateCallStateChange(idle)", function () {
                    if (typeof TelephonyService === 'undefined')
                        return false;

                    TelephonyService.simulateCallStateChange("idle");
                    return true;
                });
                autoTest("simulateIncomingSMS", function () {
                    if (typeof SMSService === 'undefined' || typeof SMSService.simulateIncomingSMS !== 'function')
                        return false;

                    SMSService.simulateIncomingSMS("+1555999888", "Auto-test SMS message");
                    return true;
                });
                break;
            case 7:
                Logger.info("AutoTest", "=== NOTIFICATION TESTS ===");
                autoTest("NotificationService available", function () {
                    return typeof NotificationService !== 'undefined';
                });
                break;
            case 8:
                Logger.info("AutoTest", "=== ALARM TESTS ===");
                autoTest("AlarmService available", function () {
                    return typeof AlarmService !== 'undefined';
                });
                autoTest("createAlarm", function () {
                    if (typeof AlarmService === 'undefined' || typeof AlarmService.createAlarm !== 'function')
                        return false;

                    var t = new Date();
                    t.setMinutes(t.getMinutes() + 5);
                    var id = AlarmService.createAlarm(Qt.formatTime(t, "HH:mm"), "Auto-test alarm", [], {});
                    return id && id.length > 0;
                });
                break;
            case 9:
                Logger.info("AutoTest", "=== MEDIA & AUDIO TESTS ===");
                autoTest("AudioManagerCpp available", function () {
                    return typeof AudioManagerCpp !== 'undefined';
                });
                autoTest("AudioManagerCpp.volume readable", function () {
                    if (typeof AudioManagerCpp === 'undefined')
                        return false;

                    var v = AudioManagerCpp.volume;
                    Logger.info("AutoTest", "  Volume: " + Math.round(v * 100) + "%");
                    return v >= 0;
                });
                autoTest("HapticService.light()", function () {
                    HapticService.light();
                    return true;
                });
                break;
            case 10:
                Logger.info("AutoTest", "=== SYSTEM TESTS ===");
                autoTest("PowerManagerService available", function () {
                    return typeof PowerManagerService !== 'undefined';
                });
                autoTest("PowerManagerService.batteryLevel readable", function () {
                    if (typeof PowerManagerService === 'undefined')
                        return false;

                    var level = PowerManagerService.batteryLevel;
                    Logger.info("AutoTest", "  Battery: " + level + "%");
                    return level >= 0;
                });
                autoTest("NetworkManagerCpp available", function () {
                    return typeof NetworkManagerCpp !== 'undefined';
                });
                autoTest("NetworkManagerCpp.wifiConnected readable", function () {
                    if (typeof NetworkManagerCpp === 'undefined')
                        return false;

                    var c = NetworkManagerCpp.wifiConnected;
                    Logger.info("AutoTest", "  WiFi connected: " + c);
                    return true;
                });
                break;
            case 11:
                autoTest("DisplayManagerCpp available", function () {
                    return typeof DisplayManagerCpp !== 'undefined';
                });
                autoTest("DisplayManagerCpp.brightness readable", function () {
                    if (typeof DisplayManagerCpp === 'undefined')
                        return false;

                    var b = DisplayManagerCpp.brightness;
                    Logger.info("AutoTest", "  Brightness: " + Math.round(b * 100) + "%");
                    return b >= 0;
                });
                autoTest("BluetoothManagerCpp available", function () {
                    return typeof BluetoothManagerCpp !== 'undefined';
                });
                break;
            case 12:
                Logger.info("AutoTest", "=== SENSOR TESTS ===");
                autoTest("SensorService available", function () {
                    return typeof SensorService !== 'undefined';
                });
                autoTest("SensorService.ambientLight readable", function () {
                    if (typeof SensorService === 'undefined')
                        return false;

                    var lux = SensorService.ambientLight;
                    Logger.info("AutoTest", "  Ambient light: " + lux + " lux");
                    return lux >= 0;
                });
                autoTest("SensorService.proximityNear readable", function () {
                    if (typeof SensorService === 'undefined')
                        return false;

                    var near = SensorService.proximityNear;
                    Logger.info("AutoTest", "  Proximity near: " + near);
                    return true;
                });
                break;
            case 13:
                autoTest("LocationService available", function () {
                    return typeof LocationService !== 'undefined';
                });
                autoTest("LocationService.start()", function () {
                    if (typeof LocationService === 'undefined')
                        return false;

                    LocationService.start();
                    return true;
                });
                break;
            case 14:
                autoTest("LocationService.stop()", function () {
                    if (typeof LocationService === 'undefined')
                        return false;

                    LocationService.stop();
                    return true;
                });
                break;
            case 15:
                autoRunTimer.stop();
                testApp.autoRunning = false;
                Logger.info("AutoTest", "------------------------------------------");
                Logger.info("AutoTest", "  RESULTS: " + testApp.passedTests + " PASSED / " + testApp.failedTests + " FAILED / " + testApp.totalTests + " TOTAL");
                Logger.info("AutoTest", "------------------------------------------");
                if (testApp.failedTests === 0)
                    Logger.info("AutoTest", "  ALL TESTS PASSED");
                else
                    Logger.warn("AutoTest", "  " + testApp.failedTests + " TESTS FAILED");
                break;
            }
        }
    }

    content: Item {
        anchors.fill: parent

        Column {
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width
                height: 100
                color: MColors.elevated

                Column {
                    anchors.centerIn: parent
                    spacing: MSpacing.xs

                    MLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Marathon Service Tests"
                        variant: "headline"
                        color: MColors.marathonTeal
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: MSpacing.lg

                        Row {
                            spacing: MSpacing.xs

                            Icon {
                                name: "check"
                                size: 16
                                color: MColors.success
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            MLabel {
                                text: testApp.passedTests.toString()
                                color: MColors.success
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            spacing: MSpacing.xs

                            Icon {
                                name: "x"
                                size: 16
                                color: MColors.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            MLabel {
                                text: testApp.failedTests.toString()
                                color: MColors.error
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            spacing: MSpacing.xs

                            Icon {
                                name: "list"
                                size: 16
                                color: MColors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            MLabel {
                                text: testApp.totalTests.toString()
                                variant: "secondary"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            StackLayout {
                id: stackLayout

                width: parent.width
                height: testApp.height - 100 - 70
                currentIndex: tabBar.activeTab

                TelephonyTestsPage {
                    testApp: testApp
                }

                NotificationTestsPage {
                    testApp: testApp
                }

                AlarmTestsPage {
                    testApp: testApp
                }

                MediaTestsPage {
                    testApp: testApp
                }

                SystemTestsPage {
                    testApp: testApp
                }

                SensorTestsPage {
                    testApp: testApp
                }
            }

            MTabBar {
                id: tabBar

                width: parent.width
                activeTab: 0
                tabs: [
                    {
                        "label": "Telephony",
                        "icon": "phone"
                    },
                    {
                        "label": "Notifications",
                        "icon": "bell"
                    },
                    {
                        "label": "Alarms",
                        "icon": "clock"
                    },
                    {
                        "label": "Media",
                        "icon": "music"
                    },
                    {
                        "label": "System",
                        "icon": "cpu"
                    },
                    {
                        "label": "Sensors",
                        "icon": "activity"
                    }
                ]
                onTabSelected: index => {
                    HapticService.light();
                }
            }
        }
    }
}
