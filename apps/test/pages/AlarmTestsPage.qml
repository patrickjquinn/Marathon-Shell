import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: root

    property var testApp
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
                        text: "Current Alarms: " + (root.alarmService ? root.alarmService.alarms.length : 0)
                        variant: "secondary"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Trigger Alarm"
                            variant: "primary"
                            onClicked: {
                                HapticService.medium();
                                if (root.alarmService && root.alarmService.triggerAlarmNow) {
                                    root.alarmService.triggerAlarmNow("Test Alarm");
                                    Logger.info("TestApp", "Triggered alarm now");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.alarmService && root.alarmService.createAlarm) {
                                    var futureTime = new Date();
                                    futureTime.setMinutes(futureTime.getMinutes() + 1);
                                    root.lastAlarmId = root.alarmService.createAlarm(Qt.formatTime(futureTime, "HH:mm"), "Test Alarm (auto trigger)", [], {});
                                    if (root.lastAlarmId) {
                                        Logger.info("TestApp", "Created trigger alarm: " + root.lastAlarmId);
                                        if (root.testApp) {
                                            root.testApp.passedTests++;
                                            root.testApp.totalTests++;
                                        }
                                    } else if (root.testApp) {
                                        Logger.warn("TestApp", "Failed to create trigger alarm");
                                        root.testApp.failedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AlarmService not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Create Alarm"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (root.alarmService && root.alarmService.createAlarm) {
                                    var futureTime = new Date();
                                    futureTime.setMinutes(futureTime.getMinutes() + 1);
                                    var alarmId = root.alarmService.createAlarm(Qt.formatTime(futureTime, "HH:mm"), "Test Alarm (+1 min)", [], {});
                                    if (alarmId) {
                                        Logger.info("TestApp", "Created alarm: " + alarmId);
                                        if (root.testApp) {
                                            root.testApp.passedTests++;
                                            root.testApp.totalTests++;
                                        }
                                    } else if (root.testApp) {
                                        Logger.warn("TestApp", "Failed to create alarm");
                                        root.testApp.failedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AlarmService not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }
                    }
                }
            }

            Connections {
                target: root.alarmService
                enabled: root.alarmService !== null
                function onAlarmTriggered(id, label) {
                    Logger.info("TestApp", "Alarm triggered: " + label);
                    if (root.testApp) {
                        root.testApp.passedTests++;
                        root.testApp.totalTests++;
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
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager not available (shell-only)");
                                    if (root.testApp) {
                                        root.testApp.failedTests++;
                                        root.testApp.totalTests++;
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
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager not available (shell-only)");
                                    if (root.testApp) {
                                        root.testApp.failedTests++;
                                        root.testApp.totalTests++;
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
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager not available (shell-only)");
                                    if (root.testApp) {
                                        root.testApp.failedTests++;
                                        root.testApp.totalTests++;
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
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else {
                                    Logger.warn("TestApp", "WakeManager.scheduleWake not available (shell-only)");
                                    if (root.testApp) {
                                        root.testApp.failedTests++;
                                        root.testApp.totalTests++;
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
