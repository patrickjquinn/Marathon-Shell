import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
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
                        text: "Current Alarms: " + AlarmManager.alarms.length
                        variant: "secondary"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Trigger Alarm"
                            variant: "primary"
                            onClicked: {
                                HapticService.medium();
                                var testAlarm = {
                                    id: "test_" + Date.now(),
                                    time: Qt.formatTime(new Date(), "HH:mm"),
                                    enabled: true,
                                    label: "Test Alarm",
                                    repeat: [],
                                    sound: "default",
                                    vibrate: true,
                                    snoozeEnabled: true,
                                    snoozeDuration: 10
                                };
                                AlarmManager.alarmTriggered(testAlarm);
                                Logger.info("TestApp", "Triggered test alarm");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Create Alarm"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                var futureTime = new Date();
                                futureTime.setMinutes(futureTime.getMinutes() + 1);
                                var alarmId = AlarmManager.createAlarm(Qt.formatTime(futureTime, "HH:mm"), "Test Alarm (+1 min)", []);
                                Logger.info("TestApp", "Created alarm: " + alarmId);
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
                                WakeManager.wake("alarm");
                                Logger.info("TestApp", "Wake: alarm");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Wake (Call)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                WakeManager.wake("call");
                                Logger.info("TestApp", "Wake: call");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Wake (Notification)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                WakeManager.wake("notification");
                                Logger.info("TestApp", "Wake: notification");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Schedule Wake"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                var wakeTime = new Date();
                                wakeTime.setMinutes(wakeTime.getMinutes() + 1);
                                WakeManager.scheduleWake(wakeTime, "test");
                                Logger.info("TestApp", "Scheduled wake in 1 minute");
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
