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
            
            Text {
                text: "🔔 Notifications"
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
                        text: "Basic Notifications"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Simple"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "test",
                                    "Test Notification",
                                    "This is a simple test notification"
                                )
                                Logger.info("TestApp", "✓ Sent simple notification")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "With Icon"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "test",
                                    "Marathon Test",
                                    "Notification with custom icon",
                                    { icon: "qrc:/images/marathon-logo.svg", category: "test" }
                                )
                                Logger.info("TestApp", "✓ Sent notification with icon")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "High Priority"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "test",
                                    "⚠️ Important",
                                    "This is a high priority notification",
                                    { priority: "high", persistent: true }
                                )
                                Logger.info("TestApp", "✓ Sent high priority notification")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "With Actions"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "test",
                                    "Interactive",
                                    "Tap an action below",
                                    { actions: ["reply", "dismiss", "snooze"], category: "message" }
                                )
                                Logger.info("TestApp", "✓ Sent notification with actions")
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
                        text: "Category Tests"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Message"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "messages",
                                    "John Doe",
                                    "Hey, how are you doing?",
                                    { category: "message", icon: "message" }
                                )
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Email"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "mail",
                                    "New Email",
                                    "You have 3 new emails",
                                    { category: "email", icon: "mail" }
                                )
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Social"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "social",
                                    "Friend Request",
                                    "Jane wants to connect with you",
                                    { category: "social", icon: "users" }
                                )
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "System"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                NotificationService.sendNotification(
                                    "system",
                                    "System Update",
                                    "A new system update is available",
                                    { category: "system", icon: "download" }
                                )
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
                        text: "Stress Tests"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Burst (10)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.medium()
                                for (var i = 0; i < 10; i++) {
                                    NotificationService.sendNotification(
                                        "test",
                                        "Burst Test " + (i + 1),
                                        "Testing notification system under load"
                                    )
                                }
                                Logger.info("TestApp", "✓ Sent 10 burst notifications")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Clear All"
                            variant: "danger"
                            onClicked: {
                                HapticService.light()
                                NotificationService.dismissAllNotifications()
                                Logger.info("TestApp", "✓ Cleared all notifications")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
        }
    }
}

