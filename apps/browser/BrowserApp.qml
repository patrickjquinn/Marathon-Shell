pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Configuration 1.0
import "BrowserLogic.js" as Logic
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property QtObject bookmarkStore: ConfigurationValue {
        key: "/apps/browser/bookmarks"
        defaultValue: "[]"
    }
    property QtObject historyStore: ConfigurationValue {
        key: "/apps/browser/history"
        defaultValue: "[]"
    }
    property QtObject tabStore: ConfigurationValue {
        key: "/apps/browser/tabs"
        defaultValue: "[]"
    }
    property QtObject engineStore: ConfigurationValue {
        key: "/apps/browser/searchEngine"
        defaultValue: "DuckDuckGo"
    }
    property QtObject engineUrlStore: ConfigurationValue {
        key: "/apps/browser/searchEngineUrl"
        defaultValue: "https://duckduckgo.com/?q="
    }
    property QtObject homepageStore: ConfigurationValue {
        key: "/apps/browser/homepage"
        defaultValue: "https://duckduckgo.com"
    }
    property QtObject maxTabsStore: ConfigurationValue {
        key: "/apps/browser/maxTabs"
        defaultValue: 12
    }
    property QtObject imported: ConfigurationValue {
        key: "/apps/browser/legacyImported"
        defaultValue: false
    }
    // The MarathonUI app kept its data in the shell's settings store.
    property var legacySettings: typeof Settings !== "undefined" ? Settings : null
    property var permissions: typeof Permissions !== "undefined" ? Permissions : null

    // Tests swap in a stub; WebEngine needs a GPU context.
    property url webLayerSource: Qt.resolvedUrl("components/WebLayer.qml")
    property Item webLayer: null

    readonly property alias tabs: tabsModel
    property int currentTabIndex: 0
    property int nextTabId: 1
    readonly property var currentTab: currentTabIndex >= 0 && currentTabIndex < tabs.count ? tabs.get(currentTabIndex) : null
    readonly property int maxTabs: parseInt(maxTabsStore.value) > 0 ? parseInt(maxTabsStore.value) : 12
    readonly property var bookmarks: Logic.parseList(bookmarkStore.value)
    readonly property var history: Logic.parseList(historyStore.value)
    readonly property string searchEngineName: engineStore.value
    readonly property string searchEngineUrl: engineUrlStore.value
    readonly property string homepageUrl: homepageStore.value
    property bool isPrivateMode: false
    property bool editingAddress: false
    property bool updatingTabUrl: false
    property var _thumbnails: ({})

    signal addressRequested

    function importLegacy() {
        if (imported.value || !legacySettings || !permissions || !permissions.hasPermission(appId, "storage"))
            return;
        const oldBookmarks = Logic.parseList(legacySettings.get("browser/bookmarks", "[]"));
        let nextBookmarks = bookmarks;
        for (const b of oldBookmarks)
            nextBookmarks = Logic.addBookmark(nextBookmarks, b.url, b.title, b.timestamp);
        bookmarkStore.value = JSON.stringify(nextBookmarks);
        const known = history.map(h => h.url);
        historyStore.value = JSON.stringify(history.concat(Logic.parseList(legacySettings.get("browser/history", "[]")).filter(h => known.indexOf(h.url) === -1)).slice(0, 100));
        if (Logic.parseList(tabStore.value).length === 0)
            tabStore.value = legacySettings.get("browser/tabs", "[]");
        engineStore.value = legacySettings.get("browser/searchEngine", engineStore.value);
        engineUrlStore.value = legacySettings.get("browser/searchEngineUrl", engineUrlStore.value);
        homepageStore.value = legacySettings.get("browser/homepage", homepageStore.value);
        maxTabsStore.value = parseInt(legacySettings.get("browser/maxTabs", maxTabsStore.value));
        imported.value = true;
    }

    function restoreTabs() {
        const rows = Logic.restoreTabs(tabStore.value, homepageUrl);
        tabs.clear();
        for (const row of rows)
            tabs.append(row);
        nextTabId = Logic.nextTabId(rows);
        currentTabIndex = 0;
    }

    function saveTabs() {
        if (isPrivateMode)
            return;
        const rows = [];
        for (let i = 0; i < tabs.count; i++)
            rows.push(tabs.get(i));
        tabStore.value = Logic.saveTabs(rows);
    }

    function createNewTab(url, focusAddress) {
        if (tabs.count >= maxTabs) {
            Notices.show(qsTr("You can have up to %1 tabs open. Close one to open another.").arg(maxTabs));
            return -1;
        }
        const id = nextTabId++;
        tabs.append(Logic.tabRow(id, url || homepageUrl, "", true));
        saveTabs();
        currentTabIndex = tabs.count - 1;
        if (focusAddress !== false)
            addressRequested();
        return id;
    }

    function indexOfTab(tabId) {
        for (let i = 0; i < tabs.count; i++) {
            if (tabs.get(i).tabId === tabId)
                return i;
        }
        return -1;
    }

    function closeTab(tabId) {
        const i = indexOfTab(tabId);
        if (i < 0)
            return;
        if (webLayer)
            webLayer.discard(i);
        delete _thumbnails[tabId];
        tabs.remove(i);
        if (tabs.count === 0) {
            createNewTab(undefined, false);
            return;
        }
        if (i < currentTabIndex || currentTabIndex >= tabs.count)
            currentTabIndex--;
        saveTabs();
    }

    function closeAllTabs() {
        for (let i = 0; webLayer && i < tabs.count; i++)
            webLayer.discard(i);
        _thumbnails = {};
        tabs.clear();
        createNewTab(undefined, false);
    }

    function switchToTab(tabId) {
        const i = indexOfTab(tabId);
        if (i >= 0)
            currentTabIndex = i;
    }

    function setPrivateMode(enabled) {
        if (isPrivateMode === enabled)
            return;
        if (enabled)
            saveTabs();
        _thumbnails = {};
        tabs.clear();
        nextTabId = 1;
        currentTabIndex = 0;
        isPrivateMode = enabled;
        if (!enabled)
            restoreTabs();
        if (tabs.count === 0)
            createNewTab(homepageUrl, false);
    }

    function navigateTo(text) {
        const target = Logic.resolveInput(text, searchEngineUrl);
        if (!target.url) {
            if (target.error)
                Notices.show(target.error);
            return;
        }
        if (!currentTab)
            return;
        updatingTabUrl = true;
        tabs.setProperty(currentTabIndex, "url", target.url);
        tabs.setProperty(currentTabIndex, "isLoading", true);
        tabs.setProperty(currentTabIndex, "loadProgress", 10);
        tabs.setProperty(currentTabIndex, "isNewTab", false);
        updatingTabUrl = false;
    }

    function setThumbnail(tabId, grab) {
        const i = indexOfTab(tabId);
        if (i < 0)
            return;
        // The grab's url lives only as long as the result object.
        _thumbnails[tabId] = grab;
        tabs.setProperty(i, "thumbnail", grab.url.toString());
    }

    function goBack() {
        if (webLayer)
            webLayer.goBack();
    }

    function goForward() {
        if (webLayer)
            webLayer.goForward();
    }

    function reloadOrStop() {
        if (webLayer)
            webLayer.reloadOrStop();
    }

    function toggleBookmark() {
        if (isPrivateMode) {
            Notices.show(qsTr("Bookmarks are off in private browsing"));
            return;
        }
        if (!currentTab || Logic.schemeBadge(currentTab.url) === "none")
            return;
        if (Logic.isBookmarked(bookmarks, currentTab.url))
            removeBookmark(currentTab.url);
        else
            bookmarkStore.value = JSON.stringify(Logic.addBookmark(bookmarks, currentTab.url, currentTab.title, Date.now()));
    }

    function removeBookmark(url) {
        bookmarkStore.value = JSON.stringify(Logic.removeBookmark(bookmarks, url));
    }

    function addToHistory(url, title) {
        if (!isPrivateMode)
            historyStore.value = JSON.stringify(Logic.addHistory(history, url, title, Date.now()));
    }

    function retitleHistory(url, title) {
        if (isPrivateMode)
            return;
        const next = Logic.retitleHistory(history, url, title);
        if (next !== history)
            historyStore.value = JSON.stringify(next);
    }

    function removeHistory(url) {
        historyStore.value = JSON.stringify(Logic.removeHistory(history, url));
    }

    function clearHistory() {
        historyStore.value = "[]";
    }

    function clearSiteData() {
        if (webLayer && webLayer.clearSiteData())
            Notices.show(qsTr("Cookies and site data cleared"));
        else
            Notices.show(qsTr("Couldn't clear cookies. Try again."));
    }

    function setSearchEngine(name, url) {
        engineStore.value = name;
        engineUrlStore.value = url;
    }

    function setHomepage(url) {
        homepageStore.value = url;
    }

    function handleBack() {
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        const page = pageStack.currentPage;
        if (page && page.closeOverlays && page.closeOverlays())
            return true;
        if (currentTab && currentTab.canGoBack) {
            goBack();
            return true;
        }
        minimizeRequested();
        return true;
    }

    function handleForward() {
        if (!currentTab || !currentTab.canGoForward)
            return false;
        goForward();
        return true;
    }

    appId: "browser"
    onApplicationActiveChanged: {
        if (applicationActive)
            return;
        saveTabs();
        if (webLayer)
            webLayer.capture();
    }
    Component.onCompleted: {
        importLegacy();
        restoreTabs();
        if (tabs.count === 0)
            createNewTab(undefined, false);
    }
    Component.onDestruction: saveTabs()

    ListModel {
        id: tabsModel
    }

    Connections {
        target: Navigation
        function onDeepLinkRequested(appId, route, params) {
            if (appId === "browser" && params && params.url)
                app.navigateTo(params.url);
        }
    }

    cover: Component {
        BrowserCover {
            title: app.currentTab ? app.currentTab.title : ""
            url: app.currentTab ? app.currentTab.url : ""
            thumbnail: app.currentTab ? app.currentTab.thumbnail : ""
            onNewTabRequested: {
                app.activate();
                if (app.pageStack.depth > 1)
                    app.pageStack.pop(app.pageStack.find(p => p.objectName === "mainPage"), PageStackAction.Immediate);
                app.createNewTab();
            }
        }
    }

    initialPage: Component {
        MainPage {
            browser: app
        }
    }
}
