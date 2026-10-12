import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "BrowserApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: valueStub
        QtObject {
            property var value
        }
    }
    Component {
        id: legacyStub
        QtObject {
            property var data: ({})
            property int reads: 0
            function get(key, fallback) {
                reads++;
                return data[key] !== undefined ? data[key] : fallback;
            }
        }
    }
    Component {
        id: permissionsStub
        QtObject {
            property bool granted: true
            function hasPermission(appId, permission) {
                return granted && appId === "browser" && permission === "storage";
            }
        }
    }
    Component {
        id: appComponent
        BrowserApp {
            width: 540
            height: 1140
        }
    }

    function value(v) {
        // Not temporary: the app outlives temporaries made before it.
        return valueStub.createObject(testCase, { value: v });
    }

    function makeApp(options) {
        const o = options || {};
        const props = {
            bookmarkStore: value(o.bookmarks || "[]"),
            historyStore: value(o.history || "[]"),
            tabStore: value(o.tabs || "[]"),
            engineStore: value("DuckDuckGo"),
            engineUrlStore: value("https://duckduckgo.com/?q="),
            homepageStore: value("https://duckduckgo.com"),
            maxTabsStore: value(o.maxTabs || 12),
            imported: value(o.imported !== false),
            legacySettings: o.legacy || null,
            permissions: o.permissions || null,
            webLayerSource: Qt.resolvedUrl("WebLayerStub.qml")
        };
        const app = createTemporaryObject(appComponent, testCase, props);
        tryCompare(app.pageStack, "depth", 1);
        tryVerify(() => app.webLayer !== null);
        return app;
    }

    function test_startsWithOneTabWithoutFocusingTheAddress() {
        const app = makeApp();
        compare(app.tabs.count, 1);
        compare(app.currentTab.url, "https://duckduckgo.com");
        verify(app.currentTab.isLoading);
        verify(!app.editingAddress);
        compare(JSON.parse(app.tabStore.value).length, 1);
    }

    function test_restoresSavedTabs() {
        const app = makeApp({ tabs: JSON.stringify([{ id: 3, url: "https://a.org", title: "A" }, { id: 7, url: "about:blank", title: "" }]) });
        compare(app.tabs.count, 2);
        compare(app.tabs.get(1).url, "https://duckduckgo.com");
        compare(app.nextTabId, 8);
        compare(app.currentTabIndex, 0);
    }

    function test_newTabFocusesAddressAndRespectsLimit() {
        const app = makeApp({ maxTabs: 2 });
        compare(app.createNewTab("https://b.org"), 2);
        compare(app.currentTabIndex, 1);
        verify(app.editingAddress);
        compare(app.createNewTab(), -1);
        compare(app.tabs.count, 2);
    }

    function test_closeTabKeepsAValidCurrentTab() {
        const app = makeApp();
        app.createNewTab("https://b.org", false);
        app.createNewTab("https://c.org", false);
        app.switchToTab(2);
        app.closeTab(2);
        compare(app.tabs.count, 2);
        compare(app.currentTab.url, "https://c.org");
        compare(app.webLayer.discarded, [1]);
        app.closeTab(3);
        compare(app.currentTabIndex, 0);
        app.closeTab(1);
        compare(app.tabs.count, 1);
        compare(app.currentTab.tabId, 4);
        verify(!app.editingAddress);
    }

    function test_closeAllTabs() {
        const app = makeApp();
        app.createNewTab("https://b.org", false);
        app.closeAllTabs();
        compare(app.tabs.count, 1);
        compare(app.currentTab.url, "https://duckduckgo.com");
    }

    function test_navigateTo() {
        const app = makeApp();
        app.navigateTo("kde.org");
        compare(app.currentTab.url, "https://kde.org");
        verify(!app.currentTab.isNewTab);
        app.navigateTo("qt quick");
        compare(app.currentTab.url, "https://duckduckgo.com/?q=qt%20quick");
        app.navigateTo("javascript:alert(1)");
        compare(app.currentTab.url, "https://duckduckgo.com/?q=qt%20quick");
    }

    function test_historyAndBookmarks() {
        const app = makeApp();
        app.addToHistory("https://a.org", "A");
        compare(JSON.parse(app.historyStore.value)[0].url, "https://a.org");
        app.retitleHistory("https://a.org", "Alpha");
        compare(app.history[0].title, "Alpha");
        app.removeHistory("https://a.org");
        compare(app.history.length, 0);
        app.navigateTo("https://b.org");
        app.toggleBookmark();
        compare(app.bookmarks[0].url, "https://b.org");
        app.toggleBookmark();
        compare(app.bookmarks.length, 0);
        app.addToHistory("https://a.org", "A");
        app.clearHistory();
        compare(app.historyStore.value, "[]");
    }

    function test_privateModeKeepsNothing() {
        const app = makeApp();
        app.navigateTo("https://kept.org");
        app.saveTabs();
        app.setPrivateMode(true);
        compare(app.tabs.count, 1);
        compare(app.currentTab.url, "https://duckduckgo.com");
        app.addToHistory("https://secret.org", "S");
        compare(app.history.length, 0);
        app.toggleBookmark();
        compare(app.bookmarks.length, 0);
        app.createNewTab("https://secret.org", false);
        compare(JSON.parse(app.tabStore.value)[0].url, "https://kept.org");
        app.setPrivateMode(false);
        compare(app.tabs.count, 1);
        compare(app.currentTab.url, "https://kept.org");
    }

    function test_settings() {
        const app = makeApp();
        app.setSearchEngine("Bing", "https://www.bing.com/search?q=");
        compare(app.searchEngineName, "Bing");
        app.navigateTo("cats");
        compare(app.currentTab.url, "https://www.bing.com/search?q=cats");
        app.setHomepage("about:blank");
        compare(app.homepageStore.value, "about:blank");
    }

    function test_clearSiteData() {
        const app = makeApp();
        app.clearSiteData();
        compare(app.webLayer.clears, 1);
    }

    function test_backGoesThroughPagesOverlaysThenHistory() {
        const app = makeApp();
        const main = app.pageStack.currentPage;
        app.pageStack.push(Qt.resolvedUrl("../pages/SettingsPage.qml"), { browser: app }, PageStackAction.Immediate);
        verify(app.handleBack());
        tryCompare(app.pageStack, "depth", 1);
        main.startEditing();
        verify(app.handleBack());
        verify(!app.editingAddress);
        app.tabs.setProperty(0, "canGoBack", true);
        verify(app.handleBack());
        compare(app.webLayer.backs, 1);
        app.tabs.setProperty(0, "canGoBack", false);
        let minimized = false;
        app.minimizeRequested.connect(() => minimized = true);
        verify(app.handleBack());
        verify(minimized);
    }

    function test_forward() {
        const app = makeApp();
        verify(!app.handleForward());
        app.tabs.setProperty(0, "canGoForward", true);
        verify(app.handleForward());
        compare(app.webLayer.forwards, 1);
    }

    function test_deepLinkOpensUrl() {
        const app = makeApp();
        Navigation.deepLinkRequested("browser", "", { url: "kde.org" });
        compare(app.currentTab.url, "https://kde.org");
        Navigation.deepLinkRequested("notes", "", { url: "qt.io" });
        compare(app.currentTab.url, "https://kde.org");
    }

    function test_thumbnailIsStoredOnTheTab() {
        const app = makeApp();
        app.setThumbnail(app.currentTab.tabId, { url: "file:///thumb.png" });
        compare(app.currentTab.thumbnail, "file:///thumb.png");
    }

    function test_importsLegacyDataOnce() {
        const legacy = legacyStub.createObject(testCase, { data: {
            "browser/bookmarks": JSON.stringify([{ url: "https://old.org", title: "Old", timestamp: 1 }]),
            "browser/history": JSON.stringify([{ url: "https://h.org", title: "H", timestamp: 1, visitCount: 2 }]),
            "browser/tabs": JSON.stringify([{ id: 5, url: "https://t.org", title: "T" }]),
            "browser/searchEngine": "Ecosia",
            "browser/searchEngineUrl": "https://www.ecosia.org/search?q=",
            "browser/homepage": "https://home.org",
            "browser/maxTabs": "4"
        } });
        const permissions = permissionsStub.createObject(testCase);
        const app = makeApp({ imported: false, legacy: legacy, permissions: permissions });
        compare(app.bookmarks[0].url, "https://old.org");
        compare(app.history[0].visitCount, 2);
        compare(app.tabs.get(0).url, "https://t.org");
        compare(app.searchEngineName, "Ecosia");
        compare(app.homepageUrl, "https://home.org");
        compare(app.maxTabs, 4);
        verify(app.imported.value);
        const reads = legacy.reads;
        app.importLegacy();
        compare(legacy.reads, reads);
    }

    function test_noImportWithoutStorageGrant() {
        const legacy = legacyStub.createObject(testCase, { data: { "browser/bookmarks": JSON.stringify([{ url: "https://old.org" }]) } });
        const permissions = permissionsStub.createObject(testCase, { granted: false });
        const app = makeApp({ imported: false, legacy: legacy, permissions: permissions });
        compare(legacy.reads, 0);
        compare(app.bookmarks.length, 0);
    }

    function test_storesAreConfigurationValues() {
        const app = createTemporaryObject(appComponent, testCase, { webLayerSource: Qt.resolvedUrl("WebLayerStub.qml"), tabStore: value("[]"), imported: value(true) });
        compare(app.bookmarkStore.key, "/apps/browser/bookmarks");
        compare(app.historyStore.key, "/apps/browser/history");
        compare(app.homepageStore.key, "/apps/browser/homepage");
    }
}
