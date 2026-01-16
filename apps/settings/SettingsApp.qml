import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

MApp {
    id: settingsApp

    appId: "settings"
    appName: "Settings"
    appIcon: "assets/icon.svg"

    content: Rectangle {
        function navigateToSettingsPage(pageName, params) {
            Logger.info("SettingsApp", "Navigate to page: " + pageName);
            var component = null;
            var pageParams = params || {};
            switch (pageName) {
            case "wifi":
                component = wifiPageComponent;
                break;
            case "bluetooth":
                component = bluetoothPageComponent;
                break;
            case "cellular":
                component = cellularPageComponent;
                break;
            case "display":
                component = displayPageComponent;
                break;
            case "sound":
                component = soundPageComponent;
                break;
            case "notifications":
                component = notificationsPageComponent;
                break;
            case "storage":
                component = storagePageComponent;
                break;
            case "battery":
                component = batteryPageComponent;
                break;
            case "about":
                component = aboutPageComponent;
                break;
            case "appmanager":
                component = appManagerPageComponent;
                break;
            case "hiddenapps":
                component = hiddenAppsPageComponent;
                break;
            case "defaultapps":
                component = defaultAppsPageComponent;
                break;
            case "appsort":
                component = appSortPageComponent;
                break;
            case "quicksettings":
                component = quickSettingsPageComponent;
                break;
            case "security":
                component = securityPageComponent;
                break;
            case "keyboard":
                component = keyboardPageComponent;
                break;
            default:
                Logger.error("SettingsApp", "Unknown page: " + pageName);
                return;
            }
            if (component)
                navigationStack.push(component, pageParams);
        }

        function navigateBack() {
            if (navigationStack.depth > 1) {
                navigationStack.pop();
                return true;
            }
            return false;
        }

        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack

            anchors.fill: parent
            initialItem: settingsMainPage
            onDepthChanged: {
                var newDepth = depth - 1;
                Logger.info("SettingsApp", "StackView depth changed: " + depth + " → navigationDepth: " + newDepth);
                settingsApp.navigationDepth = newDepth;
            }
            Component.onCompleted: {
                settingsApp.navigationDepth = depth - 1;
            }

            Connections {
                function onBackPressed() {
                    if (navigationStack.depth > 1)
                        navigationStack.pop();
                }

                target: settingsApp
            }

            pushEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: navigationStack.width
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    property: "opacity"
                    from: 0.7
                    to: 1
                    duration: Constants.animationDurationNormal
                }
            }

            pushExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -navigationStack.width * 0.3
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.7
                    duration: Constants.animationDurationNormal
                }
            }

            popEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: -navigationStack.width * 0.3
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    property: "opacity"
                    from: 0.7
                    to: 1
                    duration: Constants.animationDurationNormal
                }
            }

            popExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: navigationStack.width
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.7
                    duration: Constants.animationDurationNormal
                }
            }
        }

        Component {
            id: settingsMainPage

            SettingsMainPage {
                onNavigateToPage: page => {
                    navigateToSettingsPage(page);
                }
                onRequestClose: {
                    settingsApp.closed();
                }
            }
        }

        Component {
            id: wifiPageComponent

            WiFiPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: bluetoothPageComponent

            BluetoothPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: cellularPageComponent

            CellularPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: displayPageComponent

            DisplayPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: soundPageComponent

            SoundPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: notificationsPageComponent

            NotificationsPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: storagePageComponent

            StoragePage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: batteryPageComponent

            BatteryPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: aboutPageComponent

            AboutPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: appManagerPageComponent

            AppManagerPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: hiddenAppsPageComponent

            HiddenAppsPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: defaultAppsPageComponent

            DefaultAppsPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: appSortPageComponent

            AppSortPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: quickSettingsPageComponent

            QuickSettingsPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: securityPageComponent

            SecurityPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Component {
            id: keyboardPageComponent

            KeyboardPage {
                onNavigateBack: navigationStack.pop()
            }
        }

        Connections {
            function onDeepLinkRequested(appId, route, params) {
                if (appId === "settings") {
                    Logger.info("SettingsApp", "Deep link requested: " + route);
                    navigateToSettingsPage(route, params);
                }
            }

            function onSettingsNavigationRequested(page, subpage, params) {
                Logger.info("SettingsApp", "Legacy navigation: " + page);
                navigateToSettingsPage(page, params);
            }

            target: NavigationRouter
        }
    }
}
