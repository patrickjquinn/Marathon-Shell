import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic
import ".."

TestCase {
    id: testCase

    name: "MainPage"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent

        SettingsApp {
            width: 540
            height: 1140
        }
    }

    function init() {
        Network.reset();
        Bluetooth.reset();
        Settings.reset();
        Power.reset();
        Audio.reset();
        Navigation.reset();
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        return app;
    }

    function entry(app, name) {
        let item = null;
        tryVerify(() => (item = findChild(app.pageStack.currentPage, "entry-" + name)) !== null);
        return item;
    }

    function valueOf(item) {
        return item.Accessible.name;
    }

    function test_listsEveryCategory() {
        const app = makeApp();
        ["wifi", "bluetooth", "cellular", "display", "wallpaper", "sound", "notifications", "datetime", "battery", "storage", "keyboard", "security", "accounts", "appmanager", "defaultapps", "hiddenapps", "appsort", "quicksettings", "updates", "about", "terminal"].forEach(name => entry(app, name));
    }

    function test_summariesFollowServices() {
        const app = makeApp();
        const wifi = entry(app, "wifi");
        compare(valueOf(wifi), "Wi-Fi, On");
        Network.wifiConnected = true;
        Network.wifiSsid = "Home";
        compare(valueOf(wifi), "Wi-Fi, Home");
        const bt = entry(app, "bluetooth");
        compare(valueOf(bt), "Bluetooth, Off");
        Bluetooth.enabled = true;
        Bluetooth.pairedDevices = [{ name: "Buds", connected: true }];
        compare(valueOf(bt), "Bluetooth, Buds");
        compare(valueOf(entry(app, "battery")), "Battery, 80%");
        Power.isCharging = true;
        compare(valueOf(entry(app, "battery")), "Battery, 80% · charging");
        compare(valueOf(entry(app, "sound")), "Sounds, Volume 40%");
        compare(valueOf(entry(app, "datetime")), "Date and time, London");
        compare(valueOf(entry(app, "storage")), "Storage, 24.0 GB free");
        compare(valueOf(entry(app, "appsort")), "App grid, Automatic");
        Settings.hiddenApps = ["notes", "weather"];
        compare(valueOf(entry(app, "hiddenapps")), "Hidden apps, 2 hidden");
    }

    function test_quickSwitches() {
        const app = makeApp();
        const airplane = findChild(app.pageStack.currentPage, "airplaneSwitch");
        verify(!airplane.checked);
        airplane.clicked(null);
        verify(Network.airplaneModeEnabled);
        verify(airplane.checked);
        const dnd = findChild(app.pageStack.currentPage, "dndSwitch");
        dnd.clicked(null);
        verify(Settings.dndEnabled);
        verify(Audio.doNotDisturb);
        dnd.clicked(null);
        verify(!Settings.dndEnabled);
        verify(!Audio.doNotDisturb);
    }

    function test_search() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        const field = findChild(page, "searchField");
        const results = findChild(page, "results");
        field.text = "pin";
        compare(results.count, 1);
        verify(!findChild(page, "airplaneSwitch").visible);
        verify(!findChild(page, "noResults").enabled);
        field.text = "nothing like this";
        compare(results.count, 0);
        verify(findChild(page, "noResults").enabled);
        field.text = "";
        verify(findChild(page, "airplaneSwitch").visible);
    }

    function test_terminalLaunchesApp() {
        const app = makeApp();
        entry(app, "terminal").clicked(null);
        compare(Navigation.launched, ["terminal"]);
        compare(app.pageStack.depth, 1);
    }

    // Every category on the main page opens its own page.
    function test_everyEntryOpensItsPage() {
        const app = makeApp();
        const main = app.pageStack.currentPage;
        Logic.sections.forEach(section => section.entries.filter(e => e.page).forEach(e => {
            entry(app, e.page).clicked(null);
            tryVerify(() => app.pageStack.currentPage !== main && app.pageStack.currentPage.status === PageStatus.Active, 3000, e.page);
            const name = String(app.pageStack.currentPage);
            verify(name.indexOf(Logic.pageFile(e.page).replace(".qml", "")) === 0, e.page + " opened " + name);
            app.pageStack.pop(undefined, PageStackAction.Immediate);
            tryVerify(() => app.pageStack.currentPage === main && main.status === PageStatus.Active);
        }));
    }

    function test_everyRouteOpens() {
        const app = makeApp();
        Object.keys(Logic.pages).forEach(route => {
            verify(app.openPage("/" + route, PageStackAction.Immediate), route);
            tryVerify(() => app.pageStack.depth === 2 && app.pageStack.currentPage.status === PageStatus.Active, 3000, route);
            app.pageStack.pop(undefined, PageStackAction.Immediate);
            tryVerify(() => app.pageStack.depth === 1);
        });
    }

    function test_unknownRoute() {
        const app = makeApp();
        verify(!app.openPage("nope"));
        compare(app.pageStack.depth, 1);
    }

    function test_coverToggles() {
        const app = makeApp();
        app.toggleWifi();
        verify(!Network.wifiEnabled);
        app.toggleBluetooth();
        verify(Bluetooth.enabled);
    }
}
