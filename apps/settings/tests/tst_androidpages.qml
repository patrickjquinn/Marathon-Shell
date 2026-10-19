import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic
import ".."

TestCase {
    id: testCase

    name: "AndroidPages"
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
        AndroidApps.reset();
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

    // ListItem and Button clicks carry the mouse event.
    function tap(item) {
        item.clicked(null);
    }

    function called(name) {
        return AndroidApps.calls.filter(c => c[0] === name);
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

    // The main list has an entry only where Android is there.
    function test_mainEntry() {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        const main = app.pageStack.currentPage;
        const entry = child(main, "entry-android");
        compare(entry.value, "Running · 1 apps");
        AndroidApps.available = false;
        tryVerify(() => findChild(main, "entry-android") === null);
        compare(Logic.search("android")[0].page, "android");
    }

    function test_runtime() {
        const s = open("android");
        compare(child(s.page, "stateItem").value, "Running");
        compare(child(s.page, "versionItem").value, "13");
        compare(child(s.page, "memoryItem").value, "734.0 MB");
        compare(child(s.page, "uptimeItem").value, "2 hours");
        verify(!child(s.page, "stoppedNote").visible);
        const login = child(s.page, "startAtLoginSwitch");
        verify(login.checked);
        tap(login);
        compare(called("setStartAtLogin"), [["setStartAtLogin", false]]);
        verify(child(s.page, "resetEntry").enabled);
        AndroidApps.runtime = { state: "starting" };
        verify(!child(s.page, "resetEntry").enabled);

        AndroidApps.runtime = { state: "stopped", startAtLogin: false };
        compare(child(s.page, "stateItem").value, "Stopped");
        verify(!child(s.page, "memoryItem").visible);
        verify(!child(s.page, "uptimeItem").visible);
        verify(child(s.page, "stoppedNote").visible);
        verify(child(s.page, "resetEntry").enabled);
        verify(!child(s.page, "restartItem").visible);
        child(s.page, "startStopItem").clicked();
        compare(called("start").length, 1);
    }

    // Stopping and resetting go through the remorse timer.
    function test_stopAndReset() {
        const s = open("android");
        child(s.page, "startStopItem").clicked();
        compare(called("stop").length, 0);
        tryVerify(() => called("stop").length === 1, 10000);

        tap(child(s.page, "resetEntry"));
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AndroidResetDialog") === 0 && !s.app.pageStack.busy);
        s.app.pageStack.currentPage.accept();
        tryVerify(() => s.app.pageStack.currentPage === s.page && !s.app.pageStack.busy);
        compare(called("resetAndroid").length, 0);
        tryVerify(() => called("resetAndroid").length === 1, 10000);
    }

    // Android apps are rows of Installed apps like any other.
    function test_installedApps() {
        const s = open("appmanager");
        const row = child(s.page, "app-waydroid.org.fdroid.fdroid");
        compare(findChild(row, "subtitle").text, "Version 1.20 · Android app");
        verify(row.menu !== null);
        s.page.uninstallAndroid("org.fdroid.fdroid", "F-Droid");
        compare(called("uninstall"), [["uninstall", "org.fdroid.fdroid"]]);
        tap(row);
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AppInfoPage") === 0 && !s.app.pageStack.busy);
        compare(s.app.pageStack.currentPage.appId, "waydroid.org.fdroid.fdroid");
    }

    // appmanager/waydroid.<pkg>, as DeckardSystem forwards Android's app details.
    function test_appInfo() {
        const s = open("appmanager/waydroid.org.fdroid.fdroid");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AppInfoPage") === 0 && !s.app.pageStack.busy);
        const info = s.app.pageStack.currentPage;
        compare(child(info, "header").title, "F-Droid");
        compare(called("loadApp"), [["loadApp", "org.fdroid.fdroid"]]);
        verify(!child(info, "kindItem").visible);
        verify(!child(info, "notifySwitch").visible);
        compare(child(info, "androidKindItem").value, "Android app");
        compare(child(info, "androidVersionItem").value, "1.20");
        verify(child(info, "androidPulley").visible);

        const notify = child(info, "androidNotifySwitch");
        verify(notify.checked);
        tap(notify);
        compare(called("setNotifications"), [["setNotifications", "org.fdroid.fdroid", false]]);

        const nearby = child(info, "androidPermission-nearby");
        compare(nearby.text, "Nearby devices");
        verify(nearby.checked && nearby.enabled);
        tap(nearby);
        compare(called("setPermission"), [["setPermission", "org.fdroid.fdroid", "nearby", false]]);
        verify(!child(info, "androidPermission-camera").enabled);

        const links = child(info, "linksSwitch");
        compare(links.description, "Links to f-droid.org open in this app");
        tap(links);
        compare(called("setOpenLinks"), [["setOpenLinks", "org.fdroid.fdroid", true]]);

        const battery = child(info, "batteryCombo");
        compare(battery.currentIndex, 0);
        pick(battery, 1);
        compare(called("setBattery"), [["setBattery", "org.fdroid.fdroid", "unrestricted"]]);

        compare(child(info, "dataSizeItem").value, Logic.dataSize(4194304));
        tap(child(info, "clearCacheButton"));
        compare(called("clearCache").length, 1);
        tap(child(info, "clearDataButton"));
        compare(called("clearData").length, 0);
        tryVerify(() => called("clearData").length === 1, 10000);

        child(info, "forceStopItem").clicked();
        compare(called("forceStop").length, 1);

        // A change made elsewhere reloads the page.
        AndroidApps.appChanged("org.fdroid.fdroid");
        compare(called("loadApp").length, 2);
        AndroidApps.done("org.fdroid.fdroid", "uninstall");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AppInfoPage") !== 0 && !s.app.pageStack.busy);
    }

    // Removed elsewhere (or by our own uninstall): the page closes without an error.
    function test_appRemovedClosesThePage() {
        const s = open("appmanager/waydroid.org.fdroid.fdroid");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AppInfoPage") === 0 && !s.app.pageStack.busy);
        const info = s.app.pageStack.currentPage;
        AndroidApps.appRemoved("org.fdroid.fdroid");
        AndroidApps.failed("org.fdroid.fdroid", "loadApp", "not installed");
        AndroidApps.done("org.fdroid.fdroid", "uninstall");
        tryVerify(() => s.app.pageStack.currentPage !== info && !s.app.pageStack.busy);
        compare(s.app.pageStack.depth, 2);
        compare(called("loadApp").length, 1);
    }

    // A Marathon app's page has none of it.
    function test_marathonAppInfo() {
        const s = open("appmanager/notes");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AppInfoPage") === 0 && !s.app.pageStack.busy);
        const info = s.app.pageStack.currentPage;
        verify(!child(info, "androidDetails").visible);
        verify(!child(info, "androidPulley").visible);
        verify(child(info, "kindItem").visible);
        compare(called("loadApp").length, 0);
    }

    function test_androidApps() {
        const s = open("androidapps");
        compare(child(s.page, "androidAppList").count, 1);
        AndroidApps.apps = [];
        verify(child(s.page, "noApps").enabled);
    }

    function test_specialAccess() {
        const s = open("androidaccess/install_apps");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !s.app.pageStack.busy);
        const page = s.app.pageStack.currentPage;
        compare(page.kind, "install_apps");
        const fdroid = child(page, "access-org.fdroid.fdroid");
        verify(fdroid.checked);
        tap(fdroid);
        compare(called("setSpecialAccess"), [["setSpecialAccess", "install_apps", "org.fdroid.fdroid", false]]);

        s.app.pageStack.pop(undefined, PageStackAction.Immediate);
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AndroidAccessListPage") === 0);
        const list = s.app.pageStack.currentPage;
        tap(child(list, "access-overlay"));
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !s.app.pageStack.busy);
        verify(child(s.app.pageStack.currentPage, "noAccessApps").enabled);
    }

    function test_logic() {
        compare(Logic.duration(30), "Less than a minute");
        compare(Logic.duration(600), "10 minutes");
        compare(Logic.duration(3 * 86400), "3 days");
        compare(Logic.androidState("starting"), "Starting");
        compare(Logic.androidState(undefined), "Stopped");
        compare(Logic.androidPermission("nope").label, "nope");
        compare(Logic.androidAccess.length, 12);
        compare(Logic.dataSize(912842752), "912.8 MB");
    }
}
