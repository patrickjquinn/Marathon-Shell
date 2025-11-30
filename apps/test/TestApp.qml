import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Navigation
import "pages"

MApp {
    id: testApp
    appId: "test"
    appName: "System Test Suite"

    property int passedTests: 0
    property int failedTests: 0
    property int totalTests: 0

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

                TelephonyTestsPage {}
                NotificationTestsPage {}
                AlarmTestsPage {}
                MediaTestsPage {}
                SystemTestsPage {}
                SensorTestsPage {}
            }

            MTabBar {
                id: tabBar
                width: parent.width
                activeTab: 0

                tabs: [
                    {
                        label: "Telephony",
                        icon: "phone"
                    },
                    {
                        label: "Notifications",
                        icon: "bell"
                    },
                    {
                        label: "Alarms",
                        icon: "clock"
                    },
                    {
                        label: "Media",
                        icon: "music"
                    },
                    {
                        label: "System",
                        icon: "cpu"
                    },
                    {
                        label: "Sensors",
                        icon: "activity"
                    }
                ]

                onTabSelected: index => {
                    HapticService.light();
                }
            }
        }
    }

    Component.onCompleted: {
        Logger.info("TestApp", "System Test Suite initialized");
        Logger.info("TestApp", "Available services:");
        Logger.info("TestApp", "  - TelephonyService: " + (typeof TelephonyService !== 'undefined'));
        Logger.info("TestApp", "  - SMSService: " + (typeof SMSService !== 'undefined'));
        Logger.info("TestApp", "  - NotificationService: " + (typeof NotificationService !== 'undefined'));
        Logger.info("TestApp", "  - AlarmManager: " + (typeof AlarmManager !== 'undefined'));
        Logger.info("TestApp", "  - AudioManager: " + (typeof AudioManager !== 'undefined'));
        Logger.info("TestApp", "  - PowerManager: " + (typeof PowerManager !== 'undefined'));
        Logger.info("TestApp", "  - NetworkManager: " + (typeof NetworkManager !== 'undefined'));
        Logger.info("TestApp", "  - DisplayManager: " + (typeof DisplayManager !== 'undefined'));
    }
}
