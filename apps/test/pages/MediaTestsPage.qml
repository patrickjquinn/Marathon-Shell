import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: root

    property var testApp
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
                        text: "Volume: " + (root.audioManager ? Math.round(root.audioManager.volume * 100) : 0) + "%"
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
                                if (root.audioManager && root.audioManager.playRingtone) {
                                    root.audioManager.playRingtone();
                                    Logger.info("TestApp", "Playing ringtone");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.playRingtone not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Stop Ringtone"
                            variant: "danger"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.stopRingtone) {
                                    root.audioManager.stopRingtone();
                                    Logger.info("TestApp", "Stopped ringtone");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.stopRingtone not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Notification Sound"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.playNotificationSound) {
                                    root.audioManager.playNotificationSound();
                                    Logger.info("TestApp", "Played notification sound");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.playNotificationSound not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Alarm Sound"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.playAlarmSound) {
                                    root.audioManager.playAlarmSound();
                                    Logger.info("TestApp", "Playing alarm sound");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.playAlarmSound not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Stop Alarm"
                            variant: "danger"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.stopAlarmSound) {
                                    root.audioManager.stopAlarmSound();
                                    Logger.info("TestApp", "Stopped alarm sound");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.stopAlarmSound not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
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
                        text: "Current: " + (root.audioManager && root.audioManager.audioProfile ? root.audioManager.audioProfile : "unknown")
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
                                if (root.audioManager && root.audioManager.setAudioProfile) {
                                    root.audioManager.setAudioProfile("silent");
                                    Logger.info("TestApp", "Profile: silent");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Vibrate"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.setAudioProfile) {
                                    root.audioManager.setAudioProfile("vibrate");
                                    Logger.info("TestApp", "Profile: vibrate");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Normal"
                            variant: "primary"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.setAudioProfile) {
                                    root.audioManager.setAudioProfile("normal");
                                    Logger.info("TestApp", "Profile: normal");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Loud"
                            variant: "accent"
                            onClicked: {
                                HapticService.light();
                                if (root.audioManager && root.audioManager.setAudioProfile) {
                                    root.audioManager.setAudioProfile("loud");
                                    Logger.info("TestApp", "Profile: loud");
                                    if (root.testApp) {
                                        root.testApp.passedTests++;
                                        root.testApp.totalTests++;
                                    }
                                } else if (root.testApp) {
                                    Logger.warn("TestApp", "AudioManagerCpp.setAudioProfile not available");
                                    root.testApp.failedTests++;
                                    root.testApp.totalTests++;
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
                                if (root.testApp) {
                                    root.testApp.passedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Medium"
                            variant: "secondary"
                            onClicked: {
                                HapticService.medium();
                                Logger.info("TestApp", "Haptic: medium");
                                if (root.testApp) {
                                    root.testApp.passedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Heavy"
                            variant: "secondary"
                            onClicked: {
                                HapticService.heavy();
                                Logger.info("TestApp", "Haptic: heavy");
                                if (root.testApp) {
                                    root.testApp.passedTests++;
                                    root.testApp.totalTests++;
                                }
                            }
                        }

                        MButton {
                            text: "Pattern"
                            variant: "accent"
                            onClicked: {
                                HapticService.vibratePattern([100, 50, 100, 50, 200], 1);
                                Logger.info("TestApp", "Haptic: custom pattern");
                                if (root.testApp) {
                                    root.testApp.passedTests++;
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
