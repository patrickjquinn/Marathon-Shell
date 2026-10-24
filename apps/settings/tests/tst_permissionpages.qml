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

    name: "PermissionPages"
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

    function tap(item) {
        item.clicked(null);
    }

    function test_mainEntry() {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        verify(child(app.pageStack.currentPage, "entry-permissions"));
        compare(Logic.search("microphone")[0].page, "permissions");
    }

    // Each permission, with Marathon's words; Marathon's restricted ones aren't there.
    function test_list() {
        const s = open("permissions");
        const camera = child(s.page, "permission-camera");
        compare(camera.title, "Label camera");
        verify(findChild(s.page, "permission-system") === null);
        tap(camera);
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("PermissionAppsPage") === 0 && !s.app.pageStack.busy);
        compare(s.app.pageStack.currentPage.permission, "camera");
    }

    // One list of every app with the permission, Marathon's and Android's.
    function test_appsWithAPermission() {
        Apps.append({ id: "snap", name: "Snap", icon: "", version: "1", isProtected: false });
        const s = open("permissions/camera");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("PermissionAppsPage") === 0 && !s.app.pageStack.busy);
        const page = s.app.pageStack.currentPage;
        compare(AndroidApps.calls.filter(c => c[0] === "loadPermissionApps"), [["loadPermissionApps", "camera"]]);
        const android = child(page, "app-deckard.org.fdroid.fdroid");
        compare(android.text, "F-Droid");
        compare(android.description, "Android app");
        verify(!android.checked);
        tap(android);
        compare(AndroidApps.calls[AndroidApps.calls.length - 1], ["setPermission", "org.fdroid.fdroid", "camera", true]);
        // Weather asks for location, not the camera.
        verify(findChild(page, "app-weather") === null);

        const loc = open("permissions/location");
        tryVerify(() => String(loc.app.pageStack.currentPage).indexOf("PermissionAppsPage") === 0 && !loc.app.pageStack.busy);
        const weather = child(loc.app.pageStack.currentPage, "app-weather");
        compare(weather.text, "Weather");
        compare(weather.description, "");
        verify(!weather.checked);
        tap(weather);
        compare(Permissions.calls[Permissions.calls.length - 1], ["weather", "location", true]);
        tryVerify(() => child(loc.app.pageStack.currentPage, "app-weather").checked);
        verify(child(loc.app.pageStack.currentPage, "noApps") !== null);
    }

    function test_noApps() {
        const s = open("permissions/sms");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("PermissionAppsPage") === 0 && !s.app.pageStack.busy);
        verify(child(s.app.pageStack.currentPage, "noApps").enabled);
    }

    function test_systemAppsAreFixed() {
        const s = open("permissions/storage");
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("PermissionAppsPage") === 0 && !s.app.pageStack.busy);
        const settings = child(s.app.pageStack.currentPage, "app-settings");
        verify(!settings.enabled);
        verify(settings.checked);
        compare(settings.description, "System app");
    }
}
