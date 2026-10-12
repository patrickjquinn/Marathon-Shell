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
        const notes = child(s.page, "app-notes");
        verify(notes.menu !== null);
        s.page.uninstall("notes", "Notes");
        compare(AppInstaller.uninstalled, ["notes"]);
        AppInstaller.uninstallComplete("notes");
        compare(s.page.removing.notes, "Notes");
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

    function test_defaultApps() {
        const s = open("defaultapps");
        const browser = child(s.page, "handler-browser");
        compare(browser.value, "Browser");
        compare(child(s.page, "handler-email").value, "None");
        browser.clicked(null);
        tryVerify(() => s.app.pageStack.currentPage !== s.page && s.app.pageStack.currentPage.status === PageStatus.Active);
        const picker = s.app.pageStack.currentPage;
        compare(picker.handler, "browser");
        compare(child(picker, "appList").count, 2);
        verify(child(picker, "pick-browser").selected);
        child(picker, "pick-webby").clicked(null);
        tryVerify(() => s.app.pageStack.currentPage === s.page);
        compare(browser.value, "Webby");
    }

    function test_emptyHandler() {
        const s = open("defaultapps");
        child(s.page, "handler-files").clicked(null);
        tryVerify(() => s.app.pageStack.currentPage !== s.page && s.app.pageStack.currentPage.status === PageStatus.Active);
        verify(child(s.app.pageStack.currentPage, "placeholder").enabled);
    }

    function test_hiddenApps() {
        const s = open("hiddenapps");
        compare(child(s.page, "appList").count, 3);
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
}
