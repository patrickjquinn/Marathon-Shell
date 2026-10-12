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

    // Opens the page for a route name ("wifi", "/about", "appmanager/<appId>"); false if there is none.
    // replace drops whatever was open above the main page, for links from outside the app.
    function openPage(name, operation, replace) {
        const file = Logic.pageFile(name);
        if (file === "")
            return false;
        const arg = Logic.routeArgument(name);
        const props = arg !== "" ? { focusAppId: arg } : {};
        const main = replace ? pageStack.find(p => p.objectName === "mainPage") : null;
        // replaceAbove throws when nothing is above the main page.
        if (main && pageStack.currentPage !== main)
            pageStack.replaceAbove(main, Qt.resolvedUrl("pages/" + file), props, operation);
        else
            pageStack.push(Qt.resolvedUrl("pages/" + file), props, operation);
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
                app.openPage(route, undefined, true);
            }
        }
        function onSettingsNavigationRequested(page, subpage, params) {
            app.activate();
            app.openPage(page, undefined, true);
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
            objectName: "mainPage"
            app: app
        }
    }
}
