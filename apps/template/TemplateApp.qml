import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation
import "pages"

MApp {
    id: templateApp
    appId: "template"
    appName: "Template App"

    property var appData: []

    onAppLaunched: {
        Logger.info("TemplateApp", "App launched");
        loadAppData();
    }

    onAppResumed: {
        Logger.info("TemplateApp", "App resumed");
    }

    onAppPaused: {
        Logger.info("TemplateApp", "App paused");
        saveAppData();
    }

    onAppWillTerminate: {
        Logger.info("TemplateApp", "App terminating");
        saveAppData();
    }

    function loadAppData() {
        var savedData = SettingsManagerCpp.get("template/data", "[]");
        try {
            appData = JSON.parse(savedData);
        } catch (e) {
            Logger.error("TemplateApp", "Failed to load data: " + e);
            appData = [];
        }
        appDataChanged();
    }

    function saveAppData() {
        var data = JSON.stringify(appData);
        SettingsManagerCpp.set("template/data", data);
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack
            anchors.fill: parent
            initialItem: mainPage

            onDepthChanged: {
                templateApp.navigationDepth = depth - 1;
            }

            Component.onCompleted: {
                templateApp.navigationDepth = depth - 1;
            }

            pushEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: navigationStack.width
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
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
                    from: 1.0
                    to: 0.0
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
                    from: 0.0
                    to: 1.0
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
            }
        }
    }

    Connections {
        target: templateApp
        function onBackPressed() {
            if (navigationStack.depth > 1) {
                navigationStack.pop();
            }
        }
    }

    Component {
        id: mainPage
        MainPage {}
    }
}
