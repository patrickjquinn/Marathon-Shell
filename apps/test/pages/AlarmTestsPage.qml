import MarathonApp.Test
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    property var alarmService: typeof AlarmService !== "undefined" ? AlarmService : null
    property string lastAlarmId: ""

    Flickable {
        anchors.fill: parent
        contentHeight: alarmColumn.height
        clip: true

        Column {
            id: alarmColumn

            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg

            Row {
                spacing: MSpacing.sm

                Icon {
                    name: "clock"
                    size: 24
                    color: MColors.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                MLabel {
                    text: "Alarms & Timers"
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
                        text: "Alarm Trigger Test"
                        variant: "title"
                    }

                    MLabel {
                        text: "Current Alarms: " + (alarmService ? alarmService.alarms.length : 0)
                        variant: "secondary"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Trigger Alarm"
                            variant: "primary"
                            onClicked: {
                                HapticService.medium();
                                if (alarmService && alarmService.triggerAlarmNow) {
                                    alarmService.triggerAlarmNow("Test Alarm");
                                    Logger.info("TestApp", "Triggered alarm now");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (alarmService && alarmService.createAlarm) {
                                    var futureTime = new Date();
                                    futureTime.setMinutes(futureTime.getMinutes() + 1);
                                    lastAlarmId = alarmService.createAlarm(Qt.formatTime(futureTime, "HH:mm"), "Test Alarm (auto trigger)", [], {});
                                    if (lastAlarmId) {
                                        Logger.info("TestApp", "Created trigger alarm: " + lastAlarmId);
                                        if (testApp) {
                                            testApp.passedTests++;
                                            testApp.totalTests++;
                                        }
                                    } else if (testApp) {
                                        Logger.warn("TestApp", "Failed to create trigger alarm");
                                        testApp.failedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AlarmService not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Create Alarm"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (alarmService && alarmService.createAlarm) {
                                    var futureTime = new Date();
                                    futureTime.setMinutes(futureTime.getMinutes() + 1);
                                    var alarmId = alarmService.createAlarm(Qt.formatTime(futureTime, "HH:mm"), "Test Alarm (+1 min)", [], {});
                                    if (alarmId) {
                                        Logger.info("TestApp", "Created alarm: " + alarmId);
                                        if (testApp) {
                                            testApp.passedTests++;
                                            testApp.totalTests++;
                                        }
                                    } else if (testApp) {
                                        Logger.warn("TestApp", "Failed to create alarm");
                                        testApp.failedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AlarmService not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }
                    }
                }
            }

            Connections {
                target: alarmService
                enabled: alarmService !== null
                function onAlarmTriggered(id, label) {
                    Logger.info("TestApp", "Alarm triggered: " + label);
                    if (testApp) {
                        testApp.passedTests++;
                        testApp.totalTests++;
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
                        text: "Wake Manager Test"
                        variant: "title"
                    }

                    MLabel {
                        text: "Test system wake functionality"
                        variant: "secondary"
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Wake (Alarm)"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                if (typeof WakeManager !== 'undefined' && typeof WakeManager.wake === 'function') {
                                    WakeManager.wake("alarm");
                                    Logger.info("TestApp", "Wake: alarm");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager not available (shell-only)");
                                    if (testApp) {
                                        testApp.failedTests++;
                                        testApp.totalTests++;
                                    }
                                }
                            }
                        }

                        MButton {
                            text: "Wake (Call)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (typeof WakeManager !== 'undefined' && typeof WakeManager.wake === 'function') {
                                    WakeManager.wake("call");
                                    Logger.info("TestApp", "Wake: call");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager not available (shell-only)");
                                    if (testApp) {
                                        testApp.failedTests++;
                                        testApp.totalTests++;
                                    }
                                }
                            }
                        }

                        MButton {
                            text: "Wake (Notification)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (typeof WakeManager !== 'undefined' && typeof WakeManager.wake === 'function') {
                                    WakeManager.wake("notification");
                                    Logger.info("TestApp", "Wake: notification");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager not available (shell-only)");
                                    if (testApp) {
                                        testApp.failedTests++;
                                        testApp.totalTests++;
                                    }
                                }
                            }
                        }

                        MButton {
                            text: "Schedule Wake"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                if (typeof WakeManager !== 'undefined' && typeof WakeManager.scheduleWake === 'function') {
                                    var wakeTime = new Date();
                                    wakeTime.setMinutes(wakeTime.getMinutes() + 1);
                                    WakeManager.scheduleWake(wakeTime, "test");
                                    Logger.info("TestApp", "Scheduled wake in 1 minute");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager.scheduleWake not available (shell-only)");
                                    if (testApp) {
                                        testApp.failedTests++;
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
}
