import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

MApp {
    id: settingsApp

    appId: "settings"
    appName: "Settings"
    appIcon: "assets/icon.svg"

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack

            anchors.fill: parent
            initialItem: settingsMainPage
            onDepthChanged: {
                var newDepth = navigationStack.depth - 1;
                Logger.info("SettingsApp", "StackView depth changed: " + navigationStack.depth + " → navigationDepth: " + newDepth);
                appRouter.updateNavigationDepth();
            }

            pushEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: navigationStack.width
                    to: 0
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }

                NumberAnimation {
                    property: "opacity"
                    from: 0.9
                    to: 1
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
            }

            pushExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -navigationStack.width * MMotion.pageParallaxOffset
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }

                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.9
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
            }

            popEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: -navigationStack.width * MMotion.pageParallaxOffset
                    to: 0
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }

                NumberAnimation {
                    property: "opacity"
                    from: 0.9
                    to: 1
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
            }

            popExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: navigationStack.width
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }

                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.9
                    duration: MMotion.quick
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
            }
        }

        MAppRouter {
            id: appRouter

            appId: settingsApp.appId
            stackView: navigationStack
            navigationTarget: settingsApp
            navigationDepthTarget: SettingsController
            pageRequestedTarget: SettingsController
            backRequestedTarget: SettingsController
            routeMap: ({
                    wifi: wifiPageComponent,
                    bluetooth: bluetoothPageComponent,
                    cellular: cellularPageComponent,
                    display: displayPageComponent,
                    sound: soundPageComponent,
                    notifications: notificationsPageComponent,
                    storage: storagePageComponent,
                    battery: batteryPageComponent,
                    about: aboutPageComponent,
                    tos: termsPageComponent,
                    privacy: privacyPageComponent,
                    licenses: openSourceLicensesPageComponent,
                    appmanager: appManagerPageComponent,
                    hiddenapps: hiddenAppsPageComponent,
                    defaultapps: defaultAppsPageComponent,
                    appsort: appSortPageComponent,
                    quicksettings: quickSettingsPageComponent,
                    security: securityPageComponent,
                    keyboard: keyboardPageComponent
                })
        }

        Component {
            id: settingsMainPage

            SettingsMainPage {
                onNavigateToPage: page => {
                    SettingsController.requestPage(page);
                }
                onRequestClose: {
                    settingsApp.closed();
                }
            }
        }

        Component {
            id: wifiPageComponent

            WiFiPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: bluetoothPageComponent

            BluetoothPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: cellularPageComponent

            CellularPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: displayPageComponent

            DisplayPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: soundPageComponent

            SoundPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: notificationsPageComponent

            NotificationsPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: storagePageComponent

            StoragePage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: batteryPageComponent

            BatteryPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: aboutPageComponent

            AboutPage {
                onNavigateBack: appRouter.popRoute()
                onOpenSourceLicensesRequested: {
                    SettingsController.requestPage("licenses");
                }
            }
        }

        Component {
            id: termsPageComponent

            TermsOfServicePage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: privacyPageComponent

            PrivacyPolicyPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: openSourceLicensesPageComponent

            OpenSourceLicensesPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: appManagerPageComponent

            AppManagerPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: hiddenAppsPageComponent

            HiddenAppsPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: defaultAppsPageComponent

            DefaultAppsPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: appSortPageComponent

            AppSortPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: quickSettingsPageComponent

            QuickSettingsPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: securityPageComponent

            SecurityPage {
                onNavigateBack: appRouter.popRoute()
            }
        }

        Component {
            id: keyboardPageComponent

            KeyboardPage {
                onNavigateBack: appRouter.popRoute()
            }
        }
    }
}
