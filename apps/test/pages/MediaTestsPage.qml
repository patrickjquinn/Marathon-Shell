import MarathonApp.Test
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    property var audioManager: typeof AudioManagerCpp !== "undefined" ? AudioManagerCpp : null

    Flickable {
        anchors.fill: parent
        contentHeight: mediaColumn.height
        clip: true

        Column {
            id: mediaColumn

            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg

            Row {
                spacing: MSpacing.sm

                Icon {
                    name: "music"
                    size: 24
                    color: MColors.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                MLabel {
                    text: "Media & Audio"
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
                        text: "Audio Manager"
                        variant: "title"
                    }

                    MLabel {
                        text: "Volume: " + (audioManager ? Math.round(audioManager.volume * 100) : 0) + "%"
                        variant: "secondary"
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Play Ringtone"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.playRingtone) {
                                    audioManager.playRingtone();
                                    Logger.info("TestApp", "Playing ringtone");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.playRingtone not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Stop Ringtone"
                            variant: "danger"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.stopRingtone) {
                                    audioManager.stopRingtone();
                                    Logger.info("TestApp", "Stopped ringtone");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.stopRingtone not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Notification Sound"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.playNotificationSound) {
                                    audioManager.playNotificationSound();
                                    Logger.info("TestApp", "Played notification sound");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.playNotificationSound not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Alarm Sound"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.playAlarmSound) {
                                    audioManager.playAlarmSound();
                                    Logger.info("TestApp", "Playing alarm sound");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.playAlarmSound not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Stop Alarm"
                            variant: "danger"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.stopAlarmSound) {
                                    audioManager.stopAlarmSound();
                                    Logger.info("TestApp", "Stopped alarm sound");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.stopAlarmSound not available");
                                    testApp.failedTests++;
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
                        text: "Audio Profiles"
                        variant: "title"
                    }

                    MLabel {
                        text: "Current: " + (audioManager && audioManager.audioProfile ? audioManager.audioProfile : "unknown")
                        variant: "secondary"
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Silent"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.setAudioProfile) {
                                    audioManager.setAudioProfile("silent");
                                    Logger.info("TestApp", "Profile: silent");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Vibrate"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.setAudioProfile) {
                                    audioManager.setAudioProfile("vibrate");
                                    Logger.info("TestApp", "Profile: vibrate");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Normal"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.setAudioProfile) {
                                    audioManager.setAudioProfile("normal");
                                    Logger.info("TestApp", "Profile: normal");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    testApp.failedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Loud"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                if (audioManager && audioManager.setAudioProfile) {
                                    audioManager.setAudioProfile("loud");
                                    Logger.info("TestApp", "Profile: loud");
                                    if (testApp) {
                                        testApp.passedTests++;
                                        testApp.totalTests++;
                                    }
                                } else if (testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    testApp.failedTests++;
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
                        text: "Haptic Feedback"
                        variant: "title"
                    }

                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm

                        MButton {
                            text: "Light"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                Logger.info("TestApp", "Haptic: light");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Medium"
                            variant: "secondary"
                            onClicked: {
                                HapticService.medium();
                                Logger.info("TestApp", "Haptic: medium");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Heavy"
                            variant: "secondary"
                            onClicked: {
                                HapticService.heavy();
                                Logger.info("TestApp", "Haptic: heavy");
                                if (testApp) {
                                    testApp.passedTests++;
                                    testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Pattern"
                            variant: "accent"
                            onClicked: {
                                HapticService.vibratePattern([100, 50, 100, 50, 200], 1);
                                Logger.info("TestApp", "Haptic: custom pattern");
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
