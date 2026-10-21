import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic
import ".."

TestCase {
    id: testCase

    name: "AppPages"
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
        Settings.reset();
        Apps.reset();
        AppInstaller.reset();
        SettingsController.reset();
        Permissions.reset();
        Modem.reset();
        Display.reset();
        Haptics.reset();
    }

    function open(name) {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        verify(app.openPage(name, PageStackAction.Immediate));
        const page = app.pageStack.currentPage;
        tryCompare(page, "status", PageStatus.Active);
        return { app: app, page: page };
    }

    function child(parent, name) {
        let item = null;
        tryVerify(() => (item = findChild(parent, name)) !== null, 3000, name);
        return item;
    }

    function pick(combo, index) {
        let n = 0;
        let found = null;
        combo.menu._foreachMenuItem(function (item) {
            if (n++ === index)
                found = item;
            return found === null;
        });
        found.clicked();
    }

    function test_appManager() {
        const s = open("appmanager");
        compare(child(s.page, "appList").count, 3);
        const settings = child(s.page, "app-settings");
        verify(settings.menu === null);
        compare(findChild(settings, "subtitle").text, "Version 1.0.0 · System app");
        Apps.append({ id: "plain", name: "Plain", icon: "", version: "", isProtected: false });
        verify(!findChild(child(s.page, "app-plain"), "subtitle").visible);
        const notes = child(s.page, "app-notes");
        verify(notes.menu !== null);
        s.page.uninstall("notes", "Notes");
        compare(AppInstaller.uninstalled, ["notes"]);
        AppInstaller.uninstallComplete("notes");
        compare(s.page.removing.notes, "Notes");
    }

    // Built into the OS image but not protected, like Test Suite.
    function test_builtInAppsOfferNoUninstall() {
        Apps.append({ id: "testapp", name: "Test Suite", icon: "", version: "1.0.0", isProtected: false });
        const s = open("appmanager");
        verify(child(s.page, "app-testapp").menu === null);
        verify(child(s.page, "app-weather").menu !== null);
    }

    function test_uninstallWithRemorse() {
        const s = open("appmanager");
        const menu = child(s.page, "app-weather").openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        mouseClick(findChild(menu, "uninstallItem"));
        compare(AppInstaller.uninstalled, []);
        tryCompare(AppInstaller, "uninstalled", ["weather"], 10000);
    }

    function test_tapOpensAppInfo() {
        const s = open("appmanager");
        child(s.page, "app-settings").clicked(null);
        tryVerify(() => s.app.pageStack.currentPage.appId === "settings" && s.app.pageStack.currentPage.status === PageStatus.Active);
        const info = s.app.pageStack.currentPage;
        compare(child(info, "header").title, "Settings");
        compare(child(info, "kindItem").value, "System app");
        compare(child(info, "permissions").count, 3);
    }

    function test_appInfoRoute() {
        const app = createTemporaryObject(appComponent, testCase, { route: "appmanager/notes" });
        tryVerify(() => app.pageStack.currentPage && app.pageStack.currentPage.appId === "notes" && app.pageStack.currentPage.status === PageStatus.Active, 5000);
        const info = app.pageStack.currentPage;
        compare(app.pageStack.depth, 3);
        compare(child(info, "versionItem").value, "1.2.0");
        compare(child(info, "permissions").count, 1);
        const notify = child(info, "notifySwitch");
        verify(notify.checked);
        notify.clicked(null);
        compare(SettingsController.calls, [["notify", "notes", false]]);
    }

    function openInfo(appId) {
        const app = createTemporaryObject(appComponent, testCase, { route: "appmanager/" + appId });
        tryVerify(() => app.pageStack.currentPage && app.pageStack.currentPage.appId === appId && app.pageStack.currentPage.status === PageStatus.Active, 5000);
        return app.pageStack.currentPage;
    }

    function test_permissionSwitchesShowRealState() {
        const info = openInfo("weather");
        const network = child(info, "permission-network");
        const location = child(info, "permission-location");
        verify(network.enabled);
        verify(network.checked);
        verify(!location.checked);
        compare(network.text, "Label network");
        compare(network.description, "Description network");
    }

    function test_permissionSwitchGrantsAndRevokes() {
        const info = openInfo("weather");
        const location = child(info, "permission-location");
        location.clicked(null);
        verify(location.checked);
        verify(Permissions.hasPermission("weather", "location"));
        const network = child(info, "permission-network");
        network.clicked(null);
        verify(!network.checked);
        compare(Permissions.calls, [["weather", "location", true], ["weather", "network", false]]);
    }

    function test_permissionSwitchRevertsOnFailure() {
        const info = openInfo("weather");
        const network = child(info, "permission-network");
        Permissions.fail = true;
        network.clicked(null);
        verify(network.checked);
        compare(Permissions.calls.length, 1);
    }

    function test_permissionSwitchFollowsShellSignals() {
        const info = openInfo("weather");
        const location = child(info, "permission-location");
        Permissions.permissionGranted("weather", "location");
        verify(location.checked);
        Permissions.permissionDenied("notes", "location");
        verify(location.checked);
        Permissions.permissionDenied("weather", "location");
        verify(!location.checked);
    }

    function test_systemAppPermissionsAreFixed() {
        Permissions.granted = { "settings/system": true };
        const info = openInfo("settings");
        const system = child(info, "permission-system");
        verify(!system.enabled);
        verify(system.checked);
        verify(!child(info, "notAllowedHeader").visible);
    }

    // Only protected system apps hold a restricted permission; for any
    // other app it is listed as not allowed, as the first-launch prompt does.
    function test_restrictedPermissionsAreNotAllowed() {
        const info = openInfo("weather");
        compare(child(info, "permissions").count, 2);
        compare(findChild(info, "permission-system"), null);
        verify(child(info, "notAllowedHeader").visible);
        compare(child(info, "refusedPermissions").count, 1);
        const system = child(info, "refused-system");
        verify(system.visible);
        compare(system.label, "Label system");
        compare(system.description, "Only Marathon's system apps can have this");
    }

    function test_liveAppInfoLinkReplacesOpenPages() {
        const s = open("wifi");
        verify(s.app.openPage("appmanager/weather", PageStackAction.Immediate, true));
        tryVerify(() => s.app.pageStack.currentPage.appId === "weather" && s.app.pageStack.currentPage.status === PageStatus.Active, 5000);
        compare(s.app.pageStack.depth, 3);
        compare(Logic.routeArgument("/appmanager/weather?x=1"), "weather");
        compare(Logic.routeArgument("wifi"), "");
    }

    function test_noDefaultAppsPage() {
        compare(Logic.pageFile("defaultapps"), "");
    }

    function test_hiddenApps() {
        const s = open("hiddenapps");
        compare(child(s.page, "appList").count, 3);
        verify(!child(s.page, "hide-settings").visible);
        const notes = child(s.page, "hide-notes");
        verify(!notes.checked);
        notes.clicked(null);
        compare(Settings.hiddenApps, ["notes"]);
        verify(notes.checked);
        notes.clicked(null);
        compare(Settings.hiddenApps, []);
    }

    function test_appLayout() {
        const s = open("appsort");
        const columns = child(s.page, "columnsCombo");
        compare(columns.currentIndex, 0);
        pick(columns, 2);
        compare(Settings.appGridColumns, 4);
        child(s.page, "filterSwitch").clicked(null);
        verify(!Settings.filterMobileFriendlyApps);
        child(s.page, "nativeSwitch").clicked(null);
        verify(Settings.searchNativeApps);
        child(s.page, "badgesSwitch").clicked(null);
        verify(!Settings.showNotificationBadges);
    }

    // The handler's settings through marathon-store:// URLs; the phone
    // switch is the grid's.
    function test_storeSettings() {
        const s = open("store");
        const opened = [];
        s.page.openExternally = url => opened.push(url);
        s.page.stateDir = Qt.resolvedUrl("data/marathon-store-state").toString().replace("file://", "");
        s.page.load();
        tryVerify(() => s.page.values.antiFeatures === false);
        const anti = child(s.page, "antiFeaturesSwitch");
        verify(!anti.checked);
        verify(child(s.page, "fdroidSwitch").checked);

        const phone = child(s.page, "phoneSwitch");
        verify(phone.checked);
        phone.clicked(null);
        verify(!Settings.filterMobileFriendlyApps);
        compare(opened, []);

        child(s.page, "fdroidSwitch").clicked(null);
        compare(opened, ["marathon-store://settings/set?fdroid=0"]);
        verify(!child(s.page, "fdroidSwitch").checked);
        verify(!anti.enabled);

        const metered = child(s.page, "meteredSwitch");
        verify(metered.enabled);
        child(s.page, "autoUpdateSwitch").clicked(null);
        compare(opened[1], "marathon-store://settings/set?autoUpdate=0");
        verify(!metered.enabled);
    }

    // Before the handler has written its copy, the page shows the
    // handler's defaults.
    function test_storeSettingsDefaults() {
        const s = open("store");
        s.page.openExternally = url => {};
        s.page.stateDir = "/nonexistent/marathon-store-state";
        s.page.load();
        wait(200);
        verify(child(s.page, "flathubSwitch").checked);
        verify(child(s.page, "fdroidSwitch").checked);
        const anti = child(s.page, "antiFeaturesSwitch");
        verify(anti.checked);
        verify(anti.enabled);
        verify(child(s.page, "autoUpdateSwitch").checked);
        verify(!child(s.page, "meteredSwitch").checked);
    }

    function test_appGridSwitchIsTheStores() {
        const s = open("appsort");
        compare(child(s.page, "filterSwitch").description, "Leaves out apps not made for phones, here and in the App Store");
    }

    function test_quickSettings() {
        const s = open("quicksettings");
        compare(child(s.page, "tileList").count, Logic.tiles.length);
        const wifi = child(s.page, "tile-wifi");
        verify(wifi.checked);
        wifi.clicked(null);
        compare(Settings.enabledQuickSettingsTiles, ["bluetooth"]);
        child(s.page, "tile-torch").clicked(null);
        compare(Settings.enabledQuickSettingsTiles, ["bluetooth", "torch"]);
        s.page.resetTiles();
        compare(Settings.enabledQuickSettingsTiles, Logic.defaultTiles);
        // The shell's top menu IDs, not Settings' own names.
        compare(Logic.tiles.map(t => t.id), ["wifi", "cellular", "bluetooth", "airplane", "dnd", "torch", "location", "hotspot", "nightlight", "rotation", "autobrightness", "lowpower", "vibration", "power"]);
        compare(Logic.defaultTiles, Logic.tiles.map(t => t.id));
    }

    function test_quickSettingsHideAbsentHardware() {
        Modem.available = false;
        Display.torchAvailable = false;
        Display.rotationAvailable = false;
        Display.lightSensorAvailable = false;
        Haptics.available = false;
        const s = open("quicksettings");
        compare(child(s.page, "tileList").count, Logic.tiles.length - 5);
        ["cellular", "torch", "rotation", "autobrightness", "vibration"].forEach(id => compare(findChild(s.page, "tile-" + id), null));
        verify(child(s.page, "tile-wifi"));
    }
}
