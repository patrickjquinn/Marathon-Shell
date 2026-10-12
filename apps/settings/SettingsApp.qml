pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "SettingsLogic.js" as Logic
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property string route: typeof MARATHON_APP_ROUTE !== "undefined" ? MARATHON_APP_ROUTE : ""

    // Opens the page for a route name ("wifi", "/about"); false if there is none.
    function openPage(name, operation) {
        const file = Logic.pageFile(name);
        if (file === "")
            return false;
        pageStack.push(Qt.resolvedUrl("pages/" + file), {}, operation);
        return true;
    }

    function toggleWifi() {
        Network.toggleWifi();
    }

    function toggleBluetooth() {
        Bluetooth.enabled = !Bluetooth.enabled;
    }

    appId: "settings"
    Component.onCompleted: {
        if (route !== "")
            openPage(route, PageStackAction.Immediate);
    }

    Connections {
        target: typeof NavigationRouter !== "undefined" ? NavigationRouter : null
        ignoreUnknownSignals: true

        function onDeepLinkRequested(appId, route, params) {
            if (appId === app.appId) {
                app.activate();
                app.openPage(route);
            }
        }
        function onSettingsNavigationRequested(page, subpage, params) {
            app.activate();
            app.openPage(page);
        }
    }

    cover: Component {
        SettingsCover {
            onWifiToggled: app.toggleWifi()
            onBluetoothToggled: app.toggleBluetooth()
        }
    }

    initialPage: Component {
        MainPage {
            app: app
        }
    }
}
