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

    name: "AndroidPages"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: spyComponent
        SignalSpy {}
    }

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

    // microG: on or off, push, the account and its self-check.
    function test_googleServices() {
        const s = open("android");
        verify(called("loadGoogleServices").length > 0);
        const sw = child(s.page, "googleSwitch");
        verify(sw.visible && sw.checked);
        tap(sw);
        compare(called("setGoogleServices"), [["setGoogleServices", "enabled", false]]);
        const push = child(s.page, "googlePushSwitch");
        verify(push.checked);
        tap(push);
        compare(called("setGoogleServices")[1], ["setGoogleServices", "push", false]);
        const account = child(s.page, "googleAccountEntry");
        compare(account.title, "Sign in to Google");
        tap(account);
        compare(called("openGoogleServices"), [["openGoogleServices", "account"]]);
        AndroidApps.googleServices = { installed: true, enabled: true, push: false, accounts: ["someone@gmail.com"] };
        compare(account.title, "someone@gmail.com");
        verify(!push.checked);
        tap(child(s.page, "googleCheckEntry"));
        compare(called("openGoogleServices")[1], ["openGoogleServices", "selfcheck"]);

        AndroidApps.googleServices = { installed: true, enabled: false, push: false, accounts: [] };
        verify(sw.visible && !sw.checked);
        verify(!push.visible);
        verify(!account.visible);
        AndroidApps.googleServices = {};
        verify(!sw.visible);
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

        // Marathon's names and words for Android's permissions.
        const nearby = child(info, "androidPermission-bluetooth");
        compare(nearby.text, "Label bluetooth");
        compare(nearby.description, "Description bluetooth");
        verify(nearby.checked && nearby.enabled);
        tap(nearby);
        compare(called("setPermission"), [["setPermission", "org.fdroid.fdroid", "bluetooth", false]]);
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

    // An app's own request (Android's per-app access page) shows just its switch.
    function test_accessForOneApp() {
        AndroidApps.access = { all_files: [{ pkg: "org.fdroid.fdroid", label: "F-Droid", granted: false }, { pkg: "me.zhanghai.android.files", label: "Material Files", granted: false }] };
        const s = open("androidaccess/all_files/me.zhanghai.android.files");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !s.app.pageStack.busy);
        const page = s.app.pageStack.currentPage;
        compare(page.kind, "all_files");
        compare(child(page, "accessApps").count, 1);
        verify(child(page, "access-me.zhanghai.android.files"));
        const all = open("androidaccess/all_files");
        tryVerify(() => String(all.app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !all.app.pageStack.busy);
        compare(child(all.app.pageStack.currentPage, "accessApps").count, 2);
        const bad = open("androidaccess/../x");
        tryVerify(() => !bad.app.pageStack.busy);
        compare(String(bad.app.pageStack.currentPage).indexOf("AndroidAccessListPage"), 0);
    }

    // Android won't remove Deckard's own packages: Settings doesn't offer it.
    function test_deckardPackagesStay() {
        AndroidApps.apps = AndroidApps.apps.concat([{ pkg: "org.marathonos.deckard.notifytest", id: "waydroid.org.marathonos.deckard.notifytest", name: "Notify Test", version: "0.1.0", icon: "" }]);
        AndroidApps.details["org.marathonos.deckard.notifytest"] = Object.assign({}, AndroidApps.details["org.fdroid.fdroid"], { pkg: "org.marathonos.deckard.notifytest", label: "Notify Test" });
        const s = open("appmanager");
        verify(child(s.page, "app-waydroid.org.marathonos.deckard.notifytest").menu === null);
        verify(child(s.page, "app-waydroid.org.fdroid.fdroid").menu !== null);
        const list = open("androidapps");
        verify(child(list.page, "app-waydroid.org.marathonos.deckard.notifytest").menu === null);
        const info = open("appmanager/waydroid.org.marathonos.deckard.notifytest");
        tryVerify(() => String(info.app.pageStack.currentPage).indexOf("AppInfoPage") === 0 && !info.app.pageStack.busy);
        verify(!info.app.pageStack.currentPage.canUninstall);
        const other = open("appmanager/waydroid.org.fdroid.fdroid");
        tryVerify(() => String(other.app.pageStack.currentPage).indexOf("AppInfoPage") === 0 && !other.app.pageStack.busy);
        verify(other.app.pageStack.currentPage.canUninstall);
    }

    // Opened from an Android app's request, Back from the page it landed on goes back to the app.
    function test_backReturnsToTheLinkingApp() {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        const minimized = createTemporaryObject(spyComponent, testCase, { target: app, signalName: "minimizeRequested" });
        verify(app.openPage("androidaccess/all_files/org.fdroid.fdroid", PageStackAction.Immediate, true, true));
        tryVerify(() => String(app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !app.pageStack.busy);
        app.handleBack();
        compare(minimized.count, 1);
        compare(app.pageStack.depth, 1);

        // Further in, Back first walks back to where the link landed.
        verify(app.openPage("androidaccess", PageStackAction.Immediate, true, true));
        tryVerify(() => String(app.pageStack.currentPage).indexOf("AndroidAccessListPage") === 0 && !app.pageStack.busy);
        tap(child(app.pageStack.currentPage, "access-overlay"));
        tryVerify(() => String(app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !app.pageStack.busy);
        app.handleBack();
        tryVerify(() => String(app.pageStack.currentPage).indexOf("AndroidAccessListPage") === 0 && !app.pageStack.busy);
        compare(minimized.count, 1);
        app.handleBack();
        compare(minimized.count, 2);

        // Opened from within Settings, Back pops as ever.
        verify(app.openPage("androidaccess/all_files", PageStackAction.Immediate));
        tryVerify(() => String(app.pageStack.currentPage).indexOf("AndroidAccessPage") === 0 && !app.pageStack.busy);
        app.handleBack();
        tryVerify(() => String(app.pageStack.currentPage).indexOf("AndroidAccessListPage") === 0 && !app.pageStack.busy);
        compare(minimized.count, 2);
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
        compare(Logic.androidAccess.length, 12);
        compare(Logic.dataSize(912842752), "912.8 MB");
        compare(Logic.routeArgument("androidaccess/all_files/org.example"), "all_files/org.example");
        compare(Logic.routeArgument("appmanager/waydroid.org.example?x=1"), "waydroid.org.example");
    }
}
