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
    // fromLink: another app sent the person here, so Back from the page the
    // link landed on goes back to that app.
    function openPage(name, operation, replace, fromLink) {
        const file = Logic.pageFile(name);
        if (file === "")
            return false;
        const arg = Logic.routeArgument(name);
        const props = arg !== "" ? { focusAppId: arg } : {};
        const main = replace ? pageStack.find(p => p.objectName === "mainPage") : null;
        // replaceAbove throws when nothing is above the main page.
        let page;
        if (main && pageStack.currentPage !== main)
            page = pageStack.replaceAbove(main, Qt.resolvedUrl("pages/" + file), props, operation);
        else
            page = pageStack.push(Qt.resolvedUrl("pages/" + file), props, operation);
        linkPage = fromLink ? page : null;
        linkHasTarget = !!fromLink && arg !== "";
        return true;
    }

    // The page a link from another app opened, and whether it opens one more
    // page itself (appmanager/<app>, androidaccess/<kind>/<app>).
    property var linkPage: null
    property bool linkHasTarget: false

    // As Marathon.Silica's ApplicationWindow, plus the way back to a linking app.
    function handleBack() {
        const page = pageStack.currentPage;
        const menu = page ? _openMenu(page) : null;
        if (menu) {
            menu.close();
            return true;
        }
        if (linkPage && (page === linkPage || (linkHasTarget && pageStack.previousPage(page) === linkPage))) {
            linkPage = null;
            const main = pageStack.find(p => p.objectName === "mainPage");
            if (main && page !== main)
                pageStack.pop(main, PageStackAction.Immediate);
            minimizeRequested();
            return true;
        }
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        minimizeRequested();
        return true;
    }

    onApplicationActiveChanged: {
        if (!applicationActive)
            linkPage = null;
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
            openPage(route, PageStackAction.Immediate, false, true);
    }

    Connections {
        target: typeof NavigationRouter !== "undefined" ? NavigationRouter : null
        ignoreUnknownSignals: true

        function onDeepLinkRequested(appId, route, params) {
            if (appId === app.appId) {
                app.activate();
                app.openPage(route, undefined, true, true);
            }
        }
        function onSettingsNavigationRequested(page, subpage, params) {
            app.activate();
            app.openPage(page, undefined, true, true);
        }
    }

    SettingsActions {
        app: app
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
