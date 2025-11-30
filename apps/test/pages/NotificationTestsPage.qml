import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
    Flickable {
        anchors.fill: parent
        contentHeight: notifColumn.height
        clip: true

        Column {
            id: notifColumn
            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg

            Row {
                spacing: MSpacing.sm
                Icon {
                    name: "bell"
                    size: 24
                    color: MColors.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                MLabel {
                    text: "Notifications"
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
                        text: "Basic Notifications"
                        variant: "title"
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Simple"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("test", "Test Notification", "This is a simple test notification");
                                Logger.info("TestApp", "Sent simple notification");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "With Icon"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("test", "Marathon Test", "Notification with custom icon", {
                                    icon: "bell",
                                    category: "test"
                                });
                                Logger.info("TestApp", "Sent notification with icon");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "High Priority"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("test", "Important", "This is a high priority notification", {
                                    priority: "high",
                                    persistent: true,
                                    icon: "alert-triangle"
                                });
                                Logger.info("TestApp", "Sent high priority notification");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "With Actions"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("test", "Interactive", "Tap an action below", {
                                    actions: ["reply", "dismiss", "snooze"],
                                    category: "message",
                                    icon: "message-circle"
                                });
                                Logger.info("TestApp", "Sent notification with actions");
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
                        text: "Category Tests"
                        variant: "title"
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Message"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("messages", "John Doe", "Hey, how are you doing?", {
                                    category: "message",
                                    icon: "message-circle"
                                });
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Email"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("mail", "New Email", "You have 3 new emails", {
                                    category: "email",
                                    icon: "mail"
                                });
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Social"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("social", "Friend Request", "Jane wants to connect with you", {
                                    category: "social",
                                    icon: "users"
                                });
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "System"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                NotificationService.sendNotification("system", "System Update", "A new system update is available", {
                                    category: "system",
                                    icon: "download"
                                });
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
                        text: "Stress Tests"
                        variant: "title"
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Burst (10)"
                            variant: "accent"
                            onClicked: {
                                HapticService.medium();
                                for (var i = 0; i < 10; i++) {
                                    NotificationService.sendNotification("test", "Burst Test " + (i + 1), "Testing notification system under load", {
                                        icon: "zap"
                                    });
                                }
                                Logger.info("TestApp", "Sent 10 burst notifications");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Clear All"
                            variant: "danger"
                            onClicked: {
                                HapticService.light();
                                NotificationService.dismissAllNotifications();
                                Logger.info("TestApp", "Cleared all notifications");
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
