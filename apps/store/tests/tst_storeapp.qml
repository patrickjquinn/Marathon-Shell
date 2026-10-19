import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."
import "Fixtures.js" as Fixtures

TestCase {
    id: testCase

    name: "StoreApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent
        StoreApp {
            width: 540
            height: 1140
            store: TestBackend {}
        }
    }

    Component {
        id: squareAppComponent
        StoreApp {
            width: 720
            height: 658
            store: TestBackend {}
        }
    }

    function makeApp(component) {
        const app = createTemporaryObject(component || appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        return app;
    }

    function tabsOf(app) {
        const tabs = app.pageStack.currentPage.tabs;
        tryVerify(() => tabs.currentItem !== null && tabs.currentItem.item !== null, 3000);
        return tabs;
    }

    function showTab(app, index) {
        const tabs = tabsOf(app);
        tabs.moveTo(index, PagedView.Immediate);
        tryCompare(tabs, "currentIndex", index);
        tryVerify(() => tabs.currentItem.item !== null, 3000);
        return tabs.currentItem.item;
    }

    function pushed(app, depth) {
        tryCompare(app.pageStack, "depth", depth, 3000);
        tryCompare(app.pageStack.currentPage, "status", PageStatus.Active, 3000);
        return app.pageStack.currentPage;
    }

    function seedMaps(app) {
        const cache = {};
        cache["org.gnome.Maps"] = Fixtures.fullApp("org.gnome.Maps");
        app.store.appstreamCache = cache;
        const summaries = {};
        summaries["org.gnome.Maps"] = Fixtures.summary();
        app.store.summaryCache = summaries;
    }

    function test_threeTabsDiscoverFirst() {
        const tabs = tabsOf(makeApp());
        compare(tabs.count, 3);
        compare(tabs.model.get(0).title, "Discover");
        compare(tabs.model.get(1).title, "Apps");
        compare(tabs.model.get(2).title, "Installed");
        compare(tabs.currentIndex, 0);
        verify(findChild(tabs, "searchField") !== null);
    }

    function test_discoverSections() {
        const app = makeApp();
        const tab = showTab(app, 0);
        app.store.collections = Fixtures.collections();
        app.store.pendingUpdates = [{ "app_id": "org.example.Old" }];
        verify(findChild(tab, "heroItem").visible);
        tryCompare(findChild(tab, "updateRows"), "count", 1);
        verify(!findChild(tab, "discoverPlaceholder").enabled);
        findChild(tab, "mobileShowAll").clicked(null);
        const list = pushed(app, 2);
        compare(list.title, "Made for phones");
        compare(list.source, "collection/mobile");
        tryCompare(list, "loading", false, 5000);
        verify(findChild(list, "listPlaceholder").enabled);
        compare(findChild(list, "listPlaceholder").text, "Couldn't load apps");
    }

    function test_offlinePlaceholder() {
        const app = makeApp();
        const tab = showTab(app, 0);
        tryCompare(app.store, "catalogLoading", false, 10000);
        app.store.pendingUpdates = [];
        tryVerify(() => findChild(tab, "discoverPlaceholder").enabled, 3000);
        compare(findChild(tab, "discoverPlaceholder").text, "Can't reach Flathub");
    }

    function test_placeholderBelowSearchField() {
        const app = makeApp(squareAppComponent);
        const tab = showTab(app, 0);
        tryCompare(app.store, "catalogLoading", false, 10000);
        app.store.pendingUpdates = [];
        const placeholder = findChild(tab, "discoverPlaceholder");
        tryVerify(() => placeholder.enabled, 3000);
        const field = findChild(tab, "searchField");
        verify(placeholder.mapToItem(tab, 0, 0).y >= field.mapToItem(tab, 0, field.height).y);
    }

    function test_heroHeaderIsHonest() {
        const app = makeApp();
        const tab = showTab(app, 0);
        app.store.collections = Fixtures.collections();
        compare(findChild(tab, "heroHeader").text, "Featured");
        app.store.appOfTheDay = Fixtures.app("org.example.Day", "Day");
        compare(findChild(tab, "heroHeader").text, "App of the day");
    }

    function test_offlineUpdatesKeepAnInlineNote() {
        const app = makeApp();
        const tab = showTab(app, 0);
        tryCompare(app.store, "catalogLoading", false, 10000);
        app.store.pendingUpdates = [{ "app_id": "org.example.Old" }];
        verify(!findChild(tab, "discoverPlaceholder").enabled);
        verify(findChild(tab, "offlineNote").visible);
        app.store.pendingUpdates = [];
        verify(findChild(tab, "discoverPlaceholder").enabled);
        verify(!findChild(tab, "offlineNote").visible);
    }

    function test_searchReplacesSections() {
        const app = makeApp();
        const tab = showTab(app, 0);
        app.store.collections = Fixtures.collections();
        findChild(tab, "searchField").text = "maps";
        verify(!findChild(tab, "heroItem").parent.visible);
        tryCompare(findChild(tab, "discoverPlaceholder"), "text", "Search isn't available", 10000);
        verify(findChild(tab, "discoverPlaceholder").enabled);
        findChild(tab, "searchField").text = "";
        tryCompare(tab, "results", []);
        verify(findChild(tab, "heroItem").parent.visible);
    }

    function test_categoriesOpenLists() {
        const app = makeApp();
        const tab = showTab(app, 1);
        const rows = findChild(tab, "categoryRows");
        compare(rows.count, 11);
        rows.itemAt(3).clicked(null);
        const list = pushed(app, 2);
        compare(list.title, "Games");
        compare(list.source, "collection/category/game");
    }

    function test_appsTabCanRefresh() {
        const app = makeApp();
        const tab = showTab(app, 1);
        tryCompare(app.store, "catalogLoading", false, 10000);
        findChild(tab, "refreshItem").clicked(null);
        verify(app.store.catalogLoading);
    }

    function test_topChartsRanked() {
        const app = makeApp();
        const tab = showTab(app, 1);
        app.store.collections = Fixtures.collections();
        tryCompare(findChild(tab, "topCharts"), "count", 2);
    }

    function test_installedTab() {
        const app = makeApp();
        const tab = showTab(app, 2);
        tryCompare(findChild(tab, "updateRows"), "count", 1, 3000);
        tryCompare(findChild(tab, "installedRows"), "count", 1, 3000);
        verify(!findChild(tab, "installedPlaceholder").enabled);
        verify(app.store.opened.indexOf("marathon-store://refresh-state/all") >= 0);
    }

    function test_detailPage() {
        const app = makeApp();
        seedMaps(app);
        app.store.openDetail({ "app_id": "org.gnome.Maps", "name": "Maps" });
        const page = pushed(app, 2);
        compare(page.appId, "org.gnome.Maps");
        tryCompare(page, "fullApp", app.store.appstreamCache["org.gnome.Maps"]);
        verify(findChild(page, "desktopWarning").visible);
        tryCompare(findChild(page, "permissionRows"), "count", 2);
        compare(findChild(page, "sensitiveRows").count, 1);
        verify(findChild(page, "sensitiveSection").visible);
        compare(page.homepage, "https://apps.gnome.org/Maps/");
        compare(page.bugtracker, "");
        findChild(page, "websiteItem").clicked(null);
        compare(app.store.opened[app.store.opened.length - 1], "https://apps.gnome.org/Maps/");
        tryCompare(findChild(page, "screenshotStrip"), "count", 2);
        verify(findChild(page, "shotPlaceholder").visible);
        verify(!findChild(page, "uninstallItem").parent.visible);
        const action = findChild(page, "detailAction");
        compare(action.action, "get");
        findChild(action, "getButton").clicked(null);
        compare(app.store.opened[app.store.opened.length - 1], "marathon-store://install/org.gnome.Maps?name=Maps");
        verify(action.busy);
        verify(findChild(action, "installProgress").visible);
        verify(findChild(action, "cancelButton").visible);
        findChild(action, "cancelButton").clicked(null);
        compare(app.store.opened[app.store.opened.length - 1], "marathon-store://cancel/org.gnome.Maps");
        verify(!findChild(action, "cancelButton").visible);
        verify(!findChild(page, "detailsFailed").visible);
    }

    function test_detailPageOffline() {
        const app = makeApp();
        app.store.openDetail({ "app_id": "org.example.Away", "name": "Away" });
        const page = pushed(app, 2);
        verify(findChild(page, "detailsBusy").visible);
        tryCompare(page, "detailsLoading", false, 10000);
        verify(findChild(page, "detailsFailed").visible);
        verify(!findChild(page, "detailsBusy").visible);
        verify(!findChild(page, "facts").visible);
        verify(!findChild(page, "aboutSection").visible);
        verify(page.detailsFailed);
        findChild(page, "retryItem").clicked(null);
        tryCompare(page, "detailsLoading", false, 10000);
        verify(findChild(page, "detailsFailed").visible);
    }

    function test_rowsShowStateNotButtons() {
        const app = makeApp();
        const tab = showTab(app, 2);
        tryCompare(findChild(tab, "installedRows"), "count", 1, 3000);
        verify(findChild(tab, "getButton") === null);
        const row = findChild(tab, "installedRows").itemAt(0);
        compare(findChild(row, "stateLabel").text, "Installed");
        compare(row.menu, null);
        app.store.updateApp(row.appId);
        verify(row.menu !== null);
        app.store.cancelJob(row.appId);
        compare(row.menu, null);
    }

    function test_savedCatalogExplained() {
        const app = makeApp();
        const tab = showTab(app, 0);
        tryCompare(app.store, "catalogLoading", false, 10000);
        app.store.collections = Fixtures.collections();
        app.store.catalogSavedAt = Math.floor(Date.now() / 1000);
        verify(findChild(tab, "savedNote").visible);
        compare(findChild(tab, "savedNote").text, "Offline. Showing apps saved today. Pull down to refresh.");
        verify(!findChild(tab, "discoverPlaceholder").enabled);
    }

    function test_uninstallWithRemorse() {
        const app = makeApp();
        seedMaps(app);
        app.store.installedApps = [{ "app_id": "org.gnome.Maps", "name": "Maps" }];
        app.store.openDetail({ "app_id": "org.gnome.Maps" });
        const page = pushed(app, 2);
        verify(page.installed);
        compare(findChild(page, "detailAction").action, "open");
        page.uninstall();
        verify(app.store.opened.indexOf("marathon-store://uninstall/org.gnome.Maps") < 0);
        tryVerify(() => app.store.opened.indexOf("marathon-store://uninstall/org.gnome.Maps") >= 0, 8000);
    }

    function test_failedInstallExplained() {
        const app = makeApp();
        seedMaps(app);
        app.store.openDetail({ "app_id": "org.gnome.Maps" });
        const page = pushed(app, 2);
        const jobs = {};
        jobs["org.gnome.Maps"] = { "state": "failed", "error": "No space left on device", "ts": 1 };
        app.store.jobs = jobs;
        const label = findChild(page, "jobError");
        verify(label.visible);
        compare(label.text, "Couldn't install. Not enough storage space on this phone.");
        compare(findChild(page, "detailAction").action, "retry");
    }

    function test_screenshotViewer() {
        const app = makeApp();
        const shots = Fixtures.fullApp("org.gnome.Maps").screenshots;
        app.store.openScreenshots(shots, 1);
        const viewer = pushed(app, 2);
        compare(findChild(viewer, "screenshotPages").count, 2);
        tryCompare(viewer, "currentIndex", 1);
        tryVerify(() => findChild(viewer, "shotError").visible, 5000);
    }

    function test_notices() {
        const app = makeApp();
        compare(app.noticeFor("org.example.A", "install", { "state": "done" }), "org.example.A installed");
        compare(app.noticeFor("org.example.A", "update", { "state": "done" }), "org.example.A updated");
        compare(app.noticeFor("org.example.A", "uninstall", { "state": "removed" }), "org.example.A removed");
        compare(app.noticeFor("org.example.A", "install", { "state": "failed", "error": "Could not resolve host" }), "Couldn't install org.example.A. Couldn't reach Flathub. Check your connection and try again.");
    }

    function test_backPopsPages() {
        const app = makeApp();
        app.store.openCollection("mobile", "Made for phones");
        pushed(app, 2);
        verify(app.handleBack());
        tryCompare(app.pageStack, "depth", 1, 3000);
    }

    function test_androidAppPage() {
        const app = makeApp();
        app.store.loadAndroidCatalog(false);
        tryVerify(() => app.store.androidApps.length === 2);
        app.store.openDetail({ "app_id": "android:org.example.clock" });
        const page = pushed(app, 2);
        compare(page.name, "Tick");
        compare(page.antiFeatures, ["Tracking"]);
        compare(page.permissions, ["Use the internet", "Use the camera"]);
        verify(findChild(page, "androidAction").visible);
    }

    function test_apkConfirmation() {
        const app = makeApp();
        app.store.openApkConfirmation("/tmp/x.apk");
        const page = pushed(app, 2);
        verify(page.inspecting);
        compare(app.store.opened[app.store.opened.length - 1], "marathon-store://apk-inspect/%2Ftmp%2Fx.apk");
        app.store.apkInfo = { "path": "/tmp/x.apk", "ok": true, "pkg": "org.example.notes", "name": "Notes", "versionName": "1.2",
            "installedVersionCode": 3, "installedVersionName": "1.1", "permissions": ["android.permission.RECORD_AUDIO"], "icon": "" };
        verify(page.isUpdate);
        compare(page.permissions, ["Use the microphone"]);
        const install = findChild(page, "apkInstall");
        verify(install.visible);
        compare(install.text, "Update");
        install.clicked(null);
        compare(app.store.opened[app.store.opened.length - 1], "marathon-store://apk-install/%2Ftmp%2Fx.apk?pkg=org.example.notes&name=Notes");
        app.store.apkInfo = { "path": "/tmp/x.apk", "ok": false, "message": "not an Android app" };
        verify(findChild(page, "apkError").visible);
    }
}
