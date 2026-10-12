import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase

    name: "BrowserPages"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent
        TestBrowser {}
    }

    function makeApp(bookmarks, history) {
        const app = createTemporaryObject(appComponent, testCase);
        if (bookmarks)
            app.bookmarkStore.value = JSON.stringify(bookmarks);
        if (history)
            app.historyStore.value = JSON.stringify(history);
        tryCompare(app.pageStack, "depth", 1);
        tryVerify(() => app.webLayer !== null);
        waitForRendering(app.pageStack.currentPage);
        return app;
    }

    function settle(app, depth) {
        tryCompare(app.pageStack, "depth", depth);
        tryVerify(() => !app.pageStack.busy);
        waitForRendering(app.pageStack.currentPage);
        return app.pageStack.currentPage;
    }

    function push(app, name) {
        app.pageStack.push(Qt.resolvedUrl("../pages/" + name), { browser: app }, PageStackAction.Immediate);
        return settle(app, 2);
    }

    function test_toolbarButtonsFollowTheTab() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        const back = findChild(page, "backButton");
        const forward = findChild(page, "forwardButton");
        verify(!back.enabled);
        verify(!forward.enabled);
        app.tabs.setProperty(0, "canGoBack", true);
        app.tabs.setProperty(0, "canGoForward", true);
        verify(back.enabled && forward.enabled);
        mouseClick(back);
        page.menuPanel.show(true);
        mouseClick(forward);
        compare(app.webLayer.backs, 1);
        compare(app.webLayer.forwards, 1);
    }

    function test_addressShowsTheHostAndBadge() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        app.tabs.setProperty(0, "isNewTab", false);
        app.navigateTo("https://www.kde.org/community");
        compare(findChild(page, "hostLabel").text, "kde.org");
        compare(findChild(page, "schemeIcon").source.toString(), "image://theme/icon-s-lock");
        app.navigateTo("http://plain.org");
        compare(findChild(page, "schemeIcon").source.toString(), "image://theme/icon-s-warning");
        compare(findChild(page, "addressButton").Accessible.name, "Address: plain.org");
    }

    function test_editingTheAddressSuggestsAndNavigates() {
        const app = makeApp([{ url: "https://kde.org/", title: "KDE" }]);
        const page = app.pageStack.currentPage;
        mouseClick(findChild(page, "addressButton"));
        verify(app.editingAddress);
        const field = findChild(page, "addressField");
        verify(field.visible);
        compare(field.text, app.currentTab.url);
        field.text = "kde";
        const list = findChild(page, "suggestionView");
        tryVerify(() => list.visible && list.count === 2);
        compare(list.model[1].kind, "bookmark");
        page.open(list.model[1].value);
        verify(!app.editingAddress);
        compare(app.currentTab.url, "https://kde.org/");
    }

    function test_rejectedAddressKeepsTheTypedText() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        const before = app.currentTab.url;
        page.startEditing();
        const field = findChild(page, "addressField");
        field.text = "javascript:alert(1)";
        page.open(field.text);
        verify(app.editingAddress);
        compare(field.text, "javascript:alert(1)");
        compare(field.selectedText, "javascript:");
        compare(app.currentTab.url, before);
    }

    function test_focusedEmptyAddressOffersBookmarksAndRecent() {
        const app = makeApp([{ url: "https://kde.org/", title: "KDE" }], [{ url: "https://qt.io/", title: "Qt", timestamp: 2 }]);
        const page = app.pageStack.currentPage;
        page.startEditing();
        const list = findChild(page, "suggestionView");
        tryVerify(() => list.visible && list.count === 2);
        compare(list.model.map(s => s.kind), ["bookmark", "history"]);
    }

    function test_enterInTheAddressNavigates() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        page.startEditing();
        const field = findChild(page, "addressField");
        field.text = "qt.io";
        tryVerify(() => field.activeFocus);
        keyClick(Qt.Key_Return);
        verify(!app.editingAddress);
        compare(app.currentTab.url, "https://qt.io");
    }

    function test_tappingTheDimmerCancelsEditing() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        page.startEditing();
        mouseClick(findChild(page, "addressDimmer"), 100, 100);
        verify(!app.editingAddress);
    }

    function test_scrollingHidesAndShowsTheToolbar() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        app.tabs.setProperty(0, "isLoading", false);
        verify(page.toolbarOpen);
        app.webLayer.scrolled(400);
        verify(!page.toolbarOpen);
        app.webLayer.scrolled(390);
        verify(!page.toolbarOpen);
        app.webLayer.scrolled(200);
        verify(page.toolbarOpen);
        app.webLayer.scrolled(600);
        verify(!page.toolbarOpen);
        app.tabs.setProperty(0, "isLoading", true);
        verify(page.toolbarOpen);
        app.tabs.setProperty(0, "isLoading", false);
        app.webLayer.scrolled(0);
        verify(page.toolbarOpen);
    }

    function test_toolbarFollowsSailfishBrowser() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        const order = ["tabsButton", "backButton", "addressButton", "menuButton"].map(n => findChild(page, n).mapToItem(page, 0, 0).x);
        compare(order.slice().sort((a, b) => a - b), order);
        verify(findChild(page.menuPanel, "forwardButton") !== null);
    }

    function test_privateModeDisablesBookmarking() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        app.navigateTo("https://kde.org");
        verify(findChild(page, "bookmarkButton").enabled);
        app.setPrivateMode(true);
        app.navigateTo("https://kde.org");
        verify(!findChild(page, "bookmarkButton").enabled);
    }

    function test_tabsButtonOpensTheTabs() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        const button = findChild(page, "tabsButton");
        compare(button.Accessible.name, "1 tab open. Show tabs");
        mouseClick(button);
        const tabs = settle(app, 2);
        compare(tabs.objectName, "tabsPage");
        compare(app.webLayer.captures, 1);
    }

    function test_menuPanelActions() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        app.navigateTo("https://kde.org");
        mouseClick(findChild(page, "menuButton"));
        const panel = page.menuPanel;
        tryVerify(() => panel.open && !panel.moving);
        mouseClick(findChild(panel, "bookmarkButton"));
        compare(app.bookmarks[0].url, "https://kde.org");
        mouseClick(findChild(panel, "reloadButton"));
        compare(app.webLayer.reloads, 1);
        tryVerify(() => !panel.open && !panel.moving);
        page.menuPanel.show(true);
        mouseClick(findChild(panel, "historyRow"));
        compare(settle(app, 2).objectName, "historyPage");
    }

    function test_menuPanelNewTabAndPrivate() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        page.menuPanel.show(true);
        mouseClick(findChild(page.menuPanel, "newTabRow"));
        compare(app.tabs.count, 2);
        verify(app.editingAddress);
        page.stopEditing();
        page.menuPanel.show(true);
        mouseClick(findChild(page.menuPanel, "privateRow"));
        verify(app.isPrivateMode);
        compare(app.tabs.count, 1);
        compare(findChild(page, "schemeIcon").source.toString(), "image://theme/icon-s-privacy");
    }

    function test_tabsPage() {
        const app = makeApp();
        app.createNewTab("https://b.org", false);
        app.tabs.setProperty(1, "title", "Bee");
        const page = push(app, "TabsPage.qml");
        const grid = findChild(page, "tabsView");
        compare(grid.count, 2);
        const second = grid.itemAtIndex(1);
        compare(second.Accessible.name, "Bee, current tab");
        mouseClick(grid.itemAtIndex(0));
        settle(app, 1);
        compare(app.currentTabIndex, 0);
    }

    function test_tabsPageClosesTabs() {
        const app = makeApp();
        app.createNewTab("https://b.org", false);
        const page = push(app, "TabsPage.qml");
        const grid = findChild(page, "tabsView");
        mouseClick(findChild(grid.itemAtIndex(1), "closeTabButton"));
        compare(app.tabs.count, 1);
        tryCompare(grid, "count", 1);
    }

    function test_tabsPageNewTab() {
        const app = makeApp();
        const page = push(app, "TabsPage.qml");
        page.newTab();
        settle(app, 1);
        compare(app.tabs.count, 2);
        verify(app.editingAddress);
    }

    function test_bookmarksPage() {
        const app = makeApp([{ url: "https://kde.org", title: "KDE" }, { url: "https://qt.io", title: "Qt" }]);
        const page = push(app, "BookmarksPage.qml");
        const view = findChild(page, "bookmarksView");
        compare(view.count, 2);
        page.searchText = "qt";
        compare(view.count, 1);
        page.open("https://qt.io");
        settle(app, 1);
        compare(app.currentTab.url, "https://qt.io");
    }

    function test_bookmarksPlaceholder() {
        const app = makeApp();
        const page = push(app, "BookmarksPage.qml");
        verify(findChild(page, "placeholder").enabled);
        compare(findChild(page, "placeholder").text, "No bookmarks yet");
    }

    function test_bookmarkDeleteUsesRemorse() {
        const app = makeApp([{ url: "https://kde.org", title: "KDE" }]);
        const page = push(app, "BookmarksPage.qml");
        const view = findChild(page, "bookmarksView");
        const item = view.itemAtIndex(0);
        const remorse = item.remorseDelete(function () {
            app.removeBookmark("https://kde.org");
        });
        compare(app.bookmarks.length, 1);
        remorse.trigger();
        tryCompare(app.bookmarks, "length", 0);
    }

    function test_historyPage() {
        const now = Date.now();
        const app = makeApp(null, [
            { url: "https://a.org", title: "A", timestamp: now, visitCount: 3 },
            { url: "https://b.org", title: "B", timestamp: now - 3 * 86400000, visitCount: 1 }
        ]);
        const page = push(app, "HistoryPage.qml");
        const view = findChild(page, "historyView");
        compare(view.count, 2);
        compare(view.model.get(0).group, "Today");
        compare(view.model.get(1).group, "This week");
        page.searchText = "b.org";
        compare(view.count, 1);
        app.removeHistory("https://b.org");
        compare(view.count, 0);
        verify(findChild(page, "placeholder").enabled);
        compare(findChild(page, "placeholder").text, "No matching pages");
    }

    function test_historyEmptyInPrivateMode() {
        const app = makeApp();
        app.setPrivateMode(true);
        const page = push(app, "HistoryPage.qml");
        compare(findChild(page, "placeholder").hintText, "Private browsing doesn't keep history");
    }

    function test_settingsPage() {
        const app = makeApp();
        const page = push(app, "SettingsPage.qml");
        mouseClick(findChild(page, "privateSwitch"));
        verify(app.isPrivateMode);
        verify(findChild(page, "privateSwitch").checked);
        const engines = findChild(page, "searchEngineBox");
        compare(engines.value, "DuckDuckGo");
        const homepage = findChild(page, "homepageBox");
        compare(homepage.value, "DuckDuckGo");
        verify(!page.homepageField.visible);
    }

    function test_settingsCustomHomepage() {
        const app = makeApp();
        app.setHomepage("https://mine.org");
        const page = push(app, "SettingsPage.qml");
        compare(findChild(page, "homepageBox").value, "Custom");
        verify(page.homepageField.visible);
        page.homepageField.text = "other.org";
        page.commitHomepage();
        compare(app.homepageUrl, "https://other.org");
    }

    function test_settingsRejectsANonAddressHomepage() {
        const app = makeApp();
        app.setHomepage("https://mine.org");
        const page = push(app, "SettingsPage.qml");
        page.homepageField.text = "foo bar";
        verify(!page.commitHomepage());
        verify(page.homepageField.errorHighlight);
        compare(page.homepageField.text, "foo bar");
        compare(app.homepageUrl, "https://mine.org");
        page.homepageField.text = "foo.org";
        verify(!page.homepageField.errorHighlight);
    }

    function test_settingsClearBrowsingData() {
        const app = makeApp(null, [{ url: "https://a.org", title: "A", timestamp: 1 }]);
        const page = push(app, "SettingsPage.qml");
        mouseClick(findChild(page, "clearDataItem"));
        const dialog = settle(app, 3);
        compare(dialog.objectName, "clearDataDialog");
        findChild(dialog, "cookiesSwitch").checked = false;
        dialog.accept();
        settle(app, 2);
        compare(app.history.length, 1);
        const remorse = findChild(page, "remorse");
        remorse.trigger();
        tryCompare(app.history, "length", 0);
        compare(app.webLayer.clears, 0);
    }

    function test_clearDataDialogNeedsAChoice() {
        const app = makeApp();
        const page = push(app, "SettingsPage.qml");
        page.clearBrowsingData();
        const dialog = settle(app, 3);
        verify(dialog.canAccept);
        findChild(dialog, "historySwitch").checked = false;
        findChild(dialog, "cookiesSwitch").checked = false;
        verify(!dialog.canAccept);
    }

    function test_settingsSelectEngine() {
        const app = makeApp();
        const page = push(app, "SettingsPage.qml");
        const engines = findChild(page, "searchEngineBox");
        engines.forceActiveFocus();
        keyClick(Qt.Key_Return);
        tryVerify(() => engines._controller.menuOpen);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        tryCompare(app, "searchEngineName", "Bing");
        compare(app.searchEngineUrl, "https://www.bing.com/search?q=");
    }
}
