import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
    Flickable {
        anchors.fill: parent
        contentHeight: mediaColumn.height
        clip: true
        
        Column {
            id: mediaColumn
            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg
            
            Text {
                text: "🎵 Media & Audio"
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
                        text: "Audio Manager"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Volume: " + Math.round(AudioManager.volume * 100) + "%"
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Play Ringtone"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.playRingtone()
                                Logger.info("TestApp", "✓ Playing ringtone")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Stop Ringtone"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.stopRingtone()
                                Logger.info("TestApp", "✓ Stopped ringtone")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Notification Sound"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.playNotificationSound()
                                Logger.info("TestApp", "✓ Played notification sound")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Alarm Sound"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.playAlarmSound()
                                Logger.info("TestApp", "✓ Playing alarm sound")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Stop Alarm"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.stopAlarmSound()
                                Logger.info("TestApp", "✓ Stopped alarm sound")
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
                        text: "Audio Profiles"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Current: " + AudioManager.audioProfile
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Silent"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.setAudioProfile("silent")
                                Logger.info("TestApp", "✓ Profile: silent")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Vibrate"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.setAudioProfile("vibrate")
                                Logger.info("TestApp", "✓ Profile: vibrate")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Normal"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.setAudioProfile("normal")
                                Logger.info("TestApp", "✓ Profile: normal")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Loud"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                AudioManager.setAudioProfile("loud")
                                Logger.info("TestApp", "✓ Profile: loud")
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
                        text: "Haptic Feedback"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Light"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                Logger.info("TestApp", "✓ Haptic: light")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Medium"
                            variant: "secondary"
                            onClicked: {
                                HapticService.medium()
                                Logger.info("TestApp", "✓ Haptic: medium")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Heavy"
                            variant: "secondary"
                            onClicked: {
                                HapticService.heavy()
                                Logger.info("TestApp", "✓ Haptic: heavy")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                        
                        MButton {
                            text: "Pattern"
                            variant: "secondary"
                            onClicked: {
                                HapticService.vibratePattern([100, 50, 100, 50, 200], 1)
                                Logger.info("TestApp", "✓ Haptic: custom pattern")
                                if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                            }
                        }
                    }
                }
            }
        }
    }
}

