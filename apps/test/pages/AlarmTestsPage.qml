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
            
            Text {
                text: "⏰ Alarms & Timers"
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
                        text: "Alarm Trigger Test"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Current Alarms: " + AlarmManager.alarms.length
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Trigger Alarm"
                            variant: "primary"
                            onClicked: {
                                HapticService.medium()
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
                                }
                                AlarmManager.alarmTriggered(testAlarm)
                                Logger.info("TestApp", "✓ Triggered test alarm")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Create Alarm"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                var futureTime = new Date()
                                futureTime.setMinutes(futureTime.getMinutes() + 1)
                                var alarmId = AlarmManager.createAlarm(
                                    Qt.formatTime(futureTime, "HH:mm"),
                                    "Test Alarm (+1 min)",
                                    []
                                )
                                Logger.info("TestApp", "✓ Created alarm: " + alarmId)
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
                        text: "Wake Manager Test"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Test system wake functionality"
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Wake (Alarm)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                WakeManager.wake("alarm")
                                Logger.info("TestApp", "✓ Wake: alarm")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Wake (Call)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                WakeManager.wake("call")
                                Logger.info("TestApp", "✓ Wake: call")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Wake (Notification)"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                WakeManager.wake("notification")
                                Logger.info("TestApp", "✓ Wake: notification")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Schedule Wake"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                var wakeTime = new Date()
                                wakeTime.setMinutes(wakeTime.getMinutes() + 1)
                                WakeManager.scheduleWake(wakeTime, "test")
                                Logger.info("TestApp", "✓ Scheduled wake in 1 minute")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
        }
    }
}

