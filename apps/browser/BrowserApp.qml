import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import QtWebEngine

MApp {
    id: browserApp

    property alias tabs: tabsModel
    property int currentTabIndex: 0
    property int nextTabId: 1
    readonly property int maxTabs: {
        if (typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp) {
            var v = parseInt(SettingsManagerCpp.get("browser/maxTabs", "12"));
            if (!isNaN(v) && v > 0)
                return v;
        }
        return 12;
    }
    property var bookmarks: []
    property var history: []
    property bool isPrivateMode: false
    property bool isAppActive: true
    property var tabViewsById: ({})
    property real drawerProgress: 0
    property bool isDrawerOpen: false
    property bool isDragging: false
    property var drawerRef: null
    property var webView: null
    property bool updatingTabUrl: false
    property var urlInputRef: null
    property bool isEditingAddress: false
    property string addressEditText: ""
    property string searchEngineName: "DuckDuckGo"
    property string searchEngineUrl: "https://duckduckgo.com/?q="
    property string homepageUrl: "https://duckduckgo.com"
    property string transientMessage: ""
    property var _focusRetryItem: null
    property bool _focusRetrySelectAll: false
    property int _focusRetryAttempts: 0
    property bool _pendingAddressBarFocus: false
    property bool _pendingAddressBarSelectAll: false
    property int _pendingAddressBarAttempts: 0
    property bool addressBarWantsFocus: false

    function updateCurrentWebView() {
        var currentTab = getCurrentTab();
        if (currentTab) {
            var key = "" + currentTab.tabId;
            var view = tabViewsById[key];
            if (view) {
                webView = view;
                return;
            }
        }
        webView = null;
    }

    function currentWebView() {
        if (webView)
            return webView;

        var currentTab = getCurrentTab();
        if (!currentTab)
            return null;

        return tabViewsById["" + currentTab.tabId] || null;
    }

    function setPrivateMode(enabled) {
        if (isPrivateMode === enabled)
            return;

        var wasPrivate = isPrivateMode;
        if (!wasPrivate && enabled)
            saveTabs();

        closeDrawer();
        tabs.clear();
        nextTabId = 1;
        currentTabIndex = 0;
        isPrivateMode = enabled;
        if (enabled) {
            createNewTab(homepageUrl);
        } else {
            loadTabs();
            if (tabs.count === 0)
                createNewTab(homepageUrl);
        }
        Qt.callLater(updateCurrentWebView);
    }

    function handleBack() {
        if (isDrawerOpen) {
            closeDrawer();
            return true;
        }
        var view = currentWebView();
        if (view && view.canGoBack) {
            view.goBack();
            return true;
        }
        minimizeRequested();
        return true;
    }

    function loadBookmarks() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var savedBookmarks = SettingsManagerCpp.get("browser/bookmarks", "[]");
            try {
                bookmarks = JSON.parse(savedBookmarks);
            } catch (e) {
                Logger.error("BrowserApp", "Failed to load bookmarks: " + e);
                bookmarks = [];
            }
        } else {
            bookmarks = [];
        }
    }

    function saveBookmarks() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var data = JSON.stringify(bookmarks);
            SettingsManagerCpp.set("browser/bookmarks", data);
        }
    }

    function addBookmark(url, title) {
        for (var i = 0; i < bookmarks.length; i++) {
            if (bookmarks[i].url === url) {
                Logger.info("BrowserApp", "Bookmark already exists");
                return false;
            }
        }
        var bookmark = {
            "url": url,
            "title": title || url,
            "timestamp": Date.now()
        };
        var newBookmarks = bookmarks.slice();
        newBookmarks.push(bookmark);
        bookmarks = newBookmarks;
        bookmarksChanged();
        saveBookmarks();
        Logger.info("BrowserApp", "Added bookmark: " + title);
        return true;
    }

    function removeBookmark(url) {
        for (var i = 0; i < bookmarks.length; i++) {
            if (bookmarks[i].url === url) {
                var newBookmarks = bookmarks.slice();
                newBookmarks.splice(i, 1);
                bookmarks = newBookmarks;
                bookmarksChanged();
                saveBookmarks();
                return true;
            }
        }
        return false;
    }

    function isBookmarked(url) {
        for (var i = 0; i < bookmarks.length; i++) {
            if (bookmarks[i].url === url)
                return true;
        }
        return false;
    }

    function loadHistory() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var savedHistory = SettingsManagerCpp.get("browser/history", "[]");
            try {
                history = JSON.parse(savedHistory);
            } catch (e) {
                Logger.error("BrowserApp", "Failed to load history: " + e);
                history = [];
            }
        } else {
            history = [];
        }
    }

    function saveHistory() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var data = JSON.stringify(history);
            SettingsManagerCpp.set("browser/history", data);
        }
    }

    function updateHistoryTitle(url, title) {
        if (isPrivateMode)
            return;

        if (!url)
            return;

        var newHistory = history.slice();
        for (var i = 0; i < newHistory.length; i++) {
            if (newHistory[i].url === url) {
                if (title && newHistory[i].title !== title) {
                    newHistory[i].title = title;
                    history = newHistory;
                    historyChanged();
                    saveHistory();
                }
                return;
            }
        }
    }

    function showTransientMessage(msg) {
        browserApp.transientMessage = msg || "";
        if (browserApp.transientMessage)
            transientMessageTimer.restart();
    }

    function addToHistory(url, title) {
        if (isPrivateMode)
            return;

        var now = Date.now();
        var newHistory = history.slice();
        for (var i = 0; i < newHistory.length; i++) {
            if (newHistory[i].url === url) {
                newHistory[i].timestamp = now;
                newHistory[i].visitCount = (newHistory[i].visitCount || 1) + 1;
                newHistory[i].title = title || newHistory[i].title;
                history = newHistory;
                historyChanged();
                saveHistory();
                return;
            }
        }
        var historyItem = {
            "url": url,
            "title": title || url,
            "timestamp": now,
            "visitCount": 1
        };
        newHistory.unshift(historyItem);
        if (newHistory.length > 100)
            newHistory = newHistory.slice(0, 100);

        history = newHistory;
        historyChanged();
        saveHistory();
    }

    function clearHistory() {
        history = [];
        historyChanged();
        saveHistory();
        Logger.info("BrowserApp", "History cleared");
    }

    function loadSettings() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            searchEngineName = SettingsManagerCpp.get("browser/searchEngine", "DuckDuckGo");
            searchEngineUrl = SettingsManagerCpp.get("browser/searchEngineUrl", "https://duckduckgo.com/?q=");
            homepageUrl = SettingsManagerCpp.get("browser/homepage", "https://duckduckgo.com");
        }
    }

    function saveSettings() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            SettingsManagerCpp.set("browser/searchEngine", searchEngineName);
            SettingsManagerCpp.set("browser/searchEngineUrl", searchEngineUrl);
            SettingsManagerCpp.set("browser/homepage", homepageUrl);
        }
    }

    function loadTabs() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var savedTabs = SettingsManagerCpp.get("browser/tabs", "[]");
            if (savedTabs) {
                try {
                    var parsedTabs = JSON.parse(savedTabs);
                    tabs.clear();
                    if (Array.isArray(parsedTabs)) {
                        var maxId = 0;
                        for (var i = 0; i < parsedTabs.length; i++) {
                            var tab = parsedTabs[i];
                            tabs.append({
                                "tabId": tab.id,
                                "url": (tab.url && tab.url !== "about:blank") ? tab.url : homepageUrl,
                                "title": tab.title || "New Tab",
                                "isLoading": false,
                                "canGoBack": false,
                                "canGoForward": false,
                                "loadProgress": 0,
                                "isCrashed": false,
                                "isNewTab": false,
                                "crashCount": 0,
                                "lastCrashAt": 0
                            });
                            if (tab.id > maxId)
                                maxId = tab.id;
                        }
                        nextTabId = maxId + 1;
                    }
                } catch (e) {
                    Logger.error("BrowserApp", "Failed to load tabs: " + e);
                }
            }
        }
    }

    function saveTabs() {
        if (isPrivateMode)
            return;

        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var tabsArray = [];
            for (var i = 0; i < tabs.count; i++) {
                var tab = tabs.get(i);
                tabsArray.push({
                    "id": tab.tabId,
                    "url": tab.url,
                    "title": tab.title
                });
            }
            SettingsManagerCpp.set("browser/tabs", JSON.stringify(tabsArray));
        }
    }

    function createNewTab(url) {
        if (tabs.count >= maxTabs) {
            Logger.warn("BrowserApp", "Maximum tabs (" + maxTabs + ") reached");
            return -1;
        }
        var newTab = {
            "tabId": nextTabId++,
            "url": url || homepageUrl,
            "title": "New Tab",
            "isLoading": false,
            "canGoBack": false,
            "canGoForward": false,
            "loadProgress": 0,
            "isCrashed": false,
            "isNewTab": true,
            "crashCount": 0,
            "lastCrashAt": 0
        };
        tabs.append(newTab);
        if (!isPrivateMode)
            saveTabs();

        Logger.info("BrowserApp", "Created new tab: " + newTab.tabId);
        switchToTab(newTab.tabId);
        Qt.callLater(function () {
            browserApp.focusAddressBar(true);
        });
        return newTab.tabId;
    }

    function closeTab(tabId) {
        for (var i = 0; i < tabs.count; i++) {
            if (tabs.get(i).tabId === tabId) {
                var wasCurrent = (i === currentTabIndex);
                var viewToRemove = browserApp.tabViewsById["" + tabId];
                if (viewToRemove) {
                    try {
                        try {
                            viewToRemove.lifecycleState = WebEngineView.LifecycleState.Discarded;
                        } catch (e) {}
                        viewToRemove.stop();
                    } catch (e) {
                        Logger.warn("BrowserApp", "Error stopping view: " + e);
                    }
                }
                if (wasCurrent)
                    webView = null;

                tabs.remove(i);
                if (tabs.count === 0) {
                    createNewTab();
                } else {
                    if (i < currentTabIndex)
                        currentTabIndex--;

                    if (currentTabIndex >= tabs.count)
                        currentTabIndex = tabs.count - 1;

                    if (wasCurrent)
                        Qt.callLater(updateCurrentWebView);
                }
                if (!isPrivateMode)
                    saveTabs();

                Logger.info("BrowserApp", "Closed tab: " + tabId);
                return;
            }
        }
    }

    function closeAllTabs() {
        tabs.clear();
        createNewTab();
    }

    function switchToTab(tabId) {
        for (var i = 0; i < tabs.count; i++) {
            if (tabs.get(i).tabId === tabId) {
                currentTabIndex = i;
                Logger.info("BrowserApp", "Switched to tab: " + tabId);
                return;
            }
        }
    }

    function getCurrentTab() {
        if (currentTabIndex >= 0 && currentTabIndex < tabs.count)
            return tabs.get(currentTabIndex);

        return null;
    }

    function findBestMatch(partialText) {
        if (!partialText || partialText.length < 2)
            return "";

        partialText = partialText.toLowerCase();
        for (var i = 0; i < bookmarks.length; i++) {
            var url = bookmarks[i].url.toLowerCase();
            var cleanUrl = url.replace("https://", "").replace("http://", "").replace("www.", "");
            var hostOnly = cleanUrl.split("/")[0];
            if (hostOnly.startsWith(partialText))
                return hostOnly;
        }
        for (var j = 0; j < history.length; j++) {
            var hUrl = history[j].url.toLowerCase();
            var hCleanUrl = hUrl.replace("https://", "").replace("http://", "").replace("www.", "");
            var hHostOnly = hCleanUrl.split("/")[0];
            if (hHostOnly.startsWith(partialText))
                return hHostOnly;
        }
        return "";
    }

    function _clearAddressSuggestions() {
        addressSuggestions.clear();
    }

    function _addSuggestion(kind, display, value) {
        addressSuggestions.append({
            "kind": kind,
            "display": display,
            "value": value
        });
    }

    function _rebuildAddressSuggestions(queryText) {
        addressSuggestions.clear();
        var q = (queryText || "").trim();
        if (!q)
            return;

        var lower = q.toLowerCase();
        var looksLikeUrl = (q.indexOf(".") !== -1 && q.indexOf(" ") === -1) || lower.startsWith("http://") || lower.startsWith("https://");
        if (looksLikeUrl) {
            var goUrl = q;
            if (!(lower.startsWith("http://") || lower.startsWith("https://") || lower.startsWith("about:")))
                goUrl = "https://" + q;

            _addSuggestion("go", "Go to " + goUrl, goUrl);
        }
        _addSuggestion("search", "Search " + searchEngineName + " for \"" + q + "\"", q);
        var seen = {};
        for (var i = 0; i < bookmarks.length; i++) {
            var bUrl = bookmarks[i].url || "";
            var bTitle = bookmarks[i].title || "";
            if (bUrl.toLowerCase().indexOf(lower) !== -1 || bTitle.toLowerCase().indexOf(lower) !== -1) {
                if (bUrl && !seen[bUrl]) {
                    seen[bUrl] = true;
                    _addSuggestion("bookmark", bTitle ? (bTitle + " — " + bUrl) : bUrl, bUrl);
                    if (addressSuggestions.count >= 8)
                        return;
                }
            }
        }
        for (var j = 0; j < history.length; j++) {
            var hUrl = history[j].url || "";
            var hTitle = history[j].title || "";
            if (hUrl.toLowerCase().indexOf(lower) !== -1 || hTitle.toLowerCase().indexOf(lower) !== -1) {
                if (hUrl && !seen[hUrl]) {
                    seen[hUrl] = true;
                    _addSuggestion("history", hTitle ? (hTitle + " — " + hUrl) : hUrl, hUrl);
                    if (addressSuggestions.count >= 8)
                        return;
                }
            }
        }
    }

    function navigateTo(url) {
        Logger.debug("Browser", "navigateTo called with: " + url);
        if (!url)
            return;

        var lowerUrl = url.toLowerCase().trim();
        if (lowerUrl.startsWith("javascript:") || lowerUrl.startsWith("data:") || lowerUrl.startsWith("file:")) {
            Logger.warn("BrowserApp", "Blocked dangerous URI scheme: " + lowerUrl.split(":")[0]);
            return;
        }
        var finalUrl = url;
        if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("about:")) {
            if (url.includes(".") && !url.includes(" "))
                finalUrl = "https://" + url;
            else
                finalUrl = searchEngineUrl + encodeURIComponent(url);
        }
        var finalLower = finalUrl.toLowerCase();
        if (!(finalLower.startsWith("http://") || finalLower.startsWith("https://") || finalLower.startsWith("about:"))) {
            Logger.warn("BrowserApp", "Blocked unsupported URL: " + finalUrl);
            return;
        }
        updatingTabUrl = true;
        tabs.setProperty(currentTabIndex, "url", finalUrl);
        tabs.setProperty(currentTabIndex, "isLoading", true);
        tabs.setProperty(currentTabIndex, "loadProgress", 10);
        tabs.setProperty(currentTabIndex, "isNewTab", false);
        updatingTabUrl = false;
    }

    function _syncAddressBarFromCurrentTab() {
        var u = browserApp.urlInputRef;
        if (!u)
            return;

        if (u.activeFocus)
            return;

        var currentTab = getCurrentTab();
        u.text = currentTab ? currentTab.url : "";
    }

    function focusAddressBar(selectAllText) {
        ensureAddressBarFocus(selectAllText);
    }

    function openDrawer() {
        isDrawerOpen = true;
        drawerProgress = 1;
    }

    function closeDrawer() {
        isDrawerOpen = false;
        drawerProgress = 0;
    }

    function ensureAddressBarFocus(selectAllText) {
        var u = browserApp.urlInputRef;
        Logger.debug("BrowserApp", "ensureAddressBarFocus called, urlInputRef=" + (u ? "exists" : "null") + " selectAll=" + selectAllText);
        if (!u) {
            browserApp._pendingAddressBarFocus = true;
            browserApp._pendingAddressBarSelectAll = !!selectAllText;
            browserApp._pendingAddressBarAttempts = 0;
            addressBarPendingFocusTimer.restart();
            Logger.debug("BrowserApp", "urlInputRef not ready, starting pending timer");
            return;
        }
        browserApp._pendingAddressBarFocus = false;
        browserApp._focusRetryItem = u;
        browserApp._focusRetrySelectAll = !!selectAllText;
        browserApp._focusRetryAttempts = 0;
        Qt.callLater(function () {
            if (!browserApp._focusRetryItem)
                return;

            browserApp._focusRetryItem.forceActiveFocus();
            if (browserApp._focusRetrySelectAll)
                browserApp._focusRetryItem.selectAll();

            if (Qt.inputMethod)
                Qt.inputMethod.show();

            focusRetryTimer.restart();
        });
    }

    focus: true
    appId: "browser"
    appName: "Browser"
    appIcon: "assets/icon.svg"
    canNavigateBack: {
        var t = getCurrentTab();
        return t ? (t.canGoBack === true) : false;
    }
    canNavigateForward: {
        var t = getCurrentTab();
        return t ? (t.canGoForward === true) : false;
    }
    onCurrentTabIndexChanged: {
        Qt.callLater(updateCurrentWebView);
    }
    onAppLaunched: {
        isAppActive = true;
        launchFocusTimer.restart();
    }
    onAppResumed: {
        isAppActive = true;
    }
    Component.onCompleted: {
        Logger.info("BrowserApp", "Initializing browser...");
        addressBarWantsFocus = true;
        loadSettings();
        loadBookmarks();
        loadHistory();
        loadTabs();
        if (tabs.count === 0) {
            Logger.info("BrowserApp", "No tabs found, creating default tab");
            createNewTab();
        }
        Qt.callLater(updateCurrentWebView);
        Qt.callLater(function () {
            browserApp._syncAddressBarFromCurrentTab();
            browserApp.focusAddressBar(true);
        });
    }
    onAppPaused: {
        isAppActive = false;
        saveTabs();
        saveBookmarks();
        saveHistory();
    }
    onAppMinimized: {
        isAppActive = false;
        try {
            var keys = Object.keys(tabViewsById);
            for (var i = 0; i < keys.length; i++) {
                var v = tabViewsById[keys[i]];
                if (v)
                    v.forceDiscarded = true;
            }
        } catch (e) {
            Logger.warn("BrowserApp", "Failed to discard tabs on minimize: " + e);
        }
        _clearAddressSuggestions();
    }
    onAppRestored: {
        isAppActive = true;
        try {
            var keys = Object.keys(tabViewsById);
            for (var i = 0; i < keys.length; i++) {
                var v = tabViewsById[keys[i]];
                if (v)
                    v.forceDiscarded = false;
            }
        } catch (e) {
            Logger.warn("BrowserApp", "Failed to restore tabs after minimize: " + e);
        }
    }
    onAppClosed: {
        if (webView) {
            webView.stop();
            webView.url = "about:blank";
            webView = null;
        }
        saveTabs();
        saveBookmarks();
        saveHistory();
    }
    Component.onDestruction: {
        if (webView) {
            webView.stop();
            webView.url = "about:blank";
            webView = null;
        }
    }

    ListModel {
        id: tabsModel
    }

    WebEngineProfile {
        id: normalProfile

        httpUserAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        Component.onCompleted: {
            storageName = "normal";
            offTheRecord = false;
            httpCacheType = WebEngineProfile.DiskHttpCache;
            persistentCookiesPolicy = WebEngineProfile.AllowPersistentCookies;
        }
    }

    WebEngineProfile {
        id: privateProfile

        httpUserAgent: normalProfile.httpUserAgent
        Component.onCompleted: {
            offTheRecord = true;
            httpCacheType = WebEngineProfile.MemoryHttpCache;
            persistentCookiesPolicy = WebEngineProfile.NoPersistentCookies;
        }
    }

    ListModel {
        id: addressSuggestions
    }

    Timer {
        id: transientMessageTimer

        interval: 2000
        repeat: false
        onTriggered: browserApp.transientMessage = ""
    }

    Timer {
        id: focusRetryTimer

        interval: 16
        repeat: true
        onTriggered: {
            var item = browserApp._focusRetryItem;
            if (!item) {
                stop();
                return;
            }
            if (item.activeFocus) {
                if (browserApp._focusRetrySelectAll)
                    item.selectAll();

                stop();
                return;
            }
            item.forceActiveFocus();
            browserApp._focusRetryAttempts++;
            if (browserApp._focusRetryAttempts >= 100) {
                if (browserApp._focusRetrySelectAll)
                    item.selectAll();

                Logger.warn("BrowserApp", "Failed to focus address bar after retries");
                stop();
            }
        }
    }

    Timer {
        id: launchFocusTimer

        interval: 900
        repeat: false
        onTriggered: {
            Logger.info("BrowserApp", "Post-launch focus: claiming address bar");
            browserApp.focusAddressBar(true);
        }
    }

    Timer {
        id: addressBarPendingFocusTimer

        interval: 16
        repeat: true
        onTriggered: {
            if (!browserApp._pendingAddressBarFocus) {
                stop();
                return;
            }
            if (browserApp.urlInputRef) {
                var selectAllText = browserApp._pendingAddressBarSelectAll;
                browserApp._pendingAddressBarFocus = false;
                stop();
                browserApp.ensureAddressBarFocus(selectAllText);
                return;
            }
            browserApp._pendingAddressBarAttempts++;
            if (browserApp._pendingAddressBarAttempts > 60) {
                Logger.warn("BrowserApp", "URL bar focus requested before urlInput was ready");
                browserApp._pendingAddressBarFocus = false;
                stop();
            }
        }
    }

    Connections {
        function onBackPressed() {
            browserApp.handleBack();
        }

        function onForwardPressed() {
            var view = browserApp.currentWebView();
            if (view && view.canGoForward)
                view.goForward();
        }

        target: browserApp
    }

    Connections {
        function onDeepLinkRequested(appId, route, params) {
            if (appId === "browser") {
                Logger.info("BrowserApp", "Deep link requested with params: " + JSON.stringify(params));
                if (params && params.url) {
                    Logger.info("BrowserApp", "Opening URL from deep link: " + params.url);
                    navigateTo(params.url);
                }
            }
        }

        target: NavigationRouter
    }

    content: Rectangle {
        id: rootContent

        anchors.fill: parent
        color: MColors.background

        Column {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: contentArea

                width: parent.width
                height: parent.height - urlBar.height
                color: MColors.background

                StackLayout {
                    id: webViewStack

                    anchors.fill: parent
                    currentIndex: currentTabIndex

                    Repeater {
                        id: tabsRepeater

                        model: browserApp.tabs

                        Item {
                            id: tabDelegate

                            required property int index
                            required property int tabId
                            required property string url
                            required property bool isCrashed

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            WebView {
                                id: webView

                                anchors.fill: parent
                                focus: !urlInput.activeFocus && !browserApp.addressBarWantsFocus
                                url: tabDelegate.url
                                profile: isPrivateMode ? privateProfile : normalProfile
                                active: isAppActive && (tabDelegate.index === currentTabIndex)
                                crashed: !!tabDelegate.isCrashed
                                Component.onCompleted: {
                                    browserApp.tabViewsById["" + tabDelegate.tabId] = webView;
                                    if (tabDelegate.index === browserApp.currentTabIndex)
                                        browserApp.webView = webView;
                                }
                                Component.onDestruction: {
                                    delete browserApp.tabViewsById["" + tabDelegate.tabId];
                                    if (browserApp.webView === webView)
                                        browserApp.webView = null;
                                }
                                onCrashedChanged: {
                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        if (browserApp.tabs.get(tabDelegate.index).isCrashed !== crashed)
                                            browserApp.tabs.setProperty(tabDelegate.index, "isCrashed", crashed);
                                    }
                                }
                                onRenderProcessTerminated: function (terminationStatus, exitCode) {
                                    var status = "";
                                    switch (terminationStatus) {
                                    case WebEngineView.NormalTerminationStatus:
                                        status = "Normal";
                                        break;
                                    case WebEngineView.AbnormalTerminationStatus:
                                        status = "Abnormal";
                                        break;
                                    case WebEngineView.CrashedTerminationStatus:
                                        status = "Crashed";
                                        break;
                                    case WebEngineView.KilledTerminationStatus:
                                        status = "Killed";
                                        break;
                                    }
                                    Logger.error("Browser", "Render process terminated: " + status + " (Code: " + exitCode + ")");
                                    if (terminationStatus !== WebEngineView.NormalTerminationStatus) {
                                        if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                            browserApp.tabs.setProperty(tabDelegate.index, "crashCount", (browserApp.tabs.get(tabDelegate.index).crashCount || 0) + 1);
                                            browserApp.tabs.setProperty(tabDelegate.index, "lastCrashAt", Date.now());
                                            browserApp.tabs.setProperty(tabDelegate.index, "isCrashed", true);
                                        }
                                        crashed = true;
                                    }
                                }
                                onNewWindowRequested: request => {
                                    if (!request)
                                        return;

                                    var reqUrl = request.requestedUrl ? request.requestedUrl.toString() : "";
                                    if (reqUrl)
                                        createNewTab(reqUrl);
                                    else
                                        createNewTab("about:blank");
                                }
                                onNavigationRequested: request => {
                                    if (!request)
                                        return;

                                    var u = request.url.toString();
                                    var lu = u.toLowerCase();
                                    if (!(lu.startsWith("http://") || lu.startsWith("https://") || lu.startsWith("about:"))) {
                                        Logger.warn("BrowserApp", "Blocked navigation to unsupported scheme: " + u);
                                        request.reject();
                                        return;
                                    }
                                    request.accept();
                                }
                                onCertificateError: error => {
                                    Logger.warn("BrowserApp", "TLS certificate error for " + error.url + " (" + error.type + "): " + error.description);
                                    error.rejectCertificate();
                                }
                                onFeaturePermissionRequested: (securityOrigin, feature) => {
                                    Logger.info("BrowserApp", "Feature permission requested (" + feature + ") for " + securityOrigin);
                                    webView.grantFeaturePermission(securityOrigin, feature, false);
                                }
                                onFullScreenRequested: request => {
                                    request.accept();
                                }
                                onUrlChanged: {
                                    if (updatingTabUrl)
                                        return;

                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        if (browserApp.tabs.get(tabDelegate.index).url !== url.toString())
                                            browserApp.tabs.setProperty(tabDelegate.index, "url", url.toString());
                                    }
                                    if (tabDelegate.index === browserApp.currentTabIndex)
                                        browserApp._syncAddressBarFromCurrentTab();
                                }
                                onTitleChanged: {
                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        if (browserApp.tabs.get(tabDelegate.index).title !== title) {
                                            browserApp.tabs.setProperty(tabDelegate.index, "title", title);
                                            if (!isPrivateMode)
                                                updateHistoryTitle(url.toString(), title);
                                        }
                                    }
                                }
                                onLoadingChanged: function (loadRequest) {
                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        var isLoading = (loadRequest.status === WebEngineView.LoadStartedStatus);
                                        browserApp.tabs.setProperty(tabDelegate.index, "isLoading", isLoading);
                                        if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                                            browserApp.tabs.setProperty(tabDelegate.index, "title", title);
                                            if (!isPrivateMode)
                                                addToHistory(url.toString(), title);

                                            if (browserApp.tabs.get(tabDelegate.index).isCrashed)
                                                browserApp.tabs.setProperty(tabDelegate.index, "isCrashed", false);
                                        }
                                        if (loadRequest.status === WebEngineView.LoadFailedStatus) {}
                                    }
                                }
                                onCanGoBackChanged: {
                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        if (browserApp.tabs.get(tabDelegate.index).canGoBack !== canGoBack)
                                            browserApp.tabs.setProperty(tabDelegate.index, "canGoBack", canGoBack);
                                    }
                                }
                                onCanGoForwardChanged: {
                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        if (browserApp.tabs.get(tabDelegate.index).canGoForward !== canGoForward)
                                            browserApp.tabs.setProperty(tabDelegate.index, "canGoForward", canGoForward);
                                    }
                                }
                                onLoadProgressChanged: {
                                    if (tabDelegate.index >= 0 && tabDelegate.index < browserApp.tabs.count) {
                                        if (browserApp.tabs.get(tabDelegate.index).loadProgress !== loadProgress)
                                            browserApp.tabs.setProperty(tabDelegate.index, "loadProgress", loadProgress);
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: rightEdgeGesture

                    property real startX: 0
                    property real currentX: 0

                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Constants.gestureEdgeWidth
                    z: 1000
                    onPressed: mouse => {
                        startX = mouse.x + rightEdgeGesture.x;
                        currentX = startX;
                        isDragging = true;
                    }
                    onPositionChanged: mouse => {
                        currentX = mouse.x + rightEdgeGesture.x;
                        var deltaX = startX - currentX;
                        drawerProgress = Math.max(0, Math.min(1, deltaX / (contentArea.width * 0.85)));
                    }
                    onReleased: {
                        isDragging = false;
                        if (drawerProgress > 0.3)
                            openDrawer();
                        else
                            closeDrawer();
                    }
                }
            }

            Rectangle {
                id: urlBar

                width: parent.width
                height: Constants.touchTargetMedium + MSpacing.sm
                color: isPrivateMode ? Qt.rgba(0.5, 0, 0.5, 0.3) : MColors.surface

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: MSpacing.sm
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(0, 0, 0, 0.72)
                    border.width: Constants.borderWidthThin
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    visible: browserApp.transientMessage !== ""
                    opacity: visible ? 1 : 0
                    z: 5000
                    implicitWidth: toastText.implicitWidth + MSpacing.sm * 2
                    implicitHeight: toastText.implicitHeight + MSpacing.sm * 2

                    Text {
                        id: toastText

                        text: browserApp.transientMessage
                        color: "white"
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        anchors.centerIn: parent
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }

                Rectangle {
                    id: loadingProgress

                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    height: Constants.borderWidthThick
                    width: {
                        if (browserApp.updatingTabUrl)
                            return parent.width * 0.2;

                        var currentTab = getCurrentTab();
                        if (currentTab && currentTab.isLoading && currentTab.loadProgress)
                            return parent.width * (currentTab.loadProgress / 100);

                        return 0;
                    }
                    color: MColors.accent
                    visible: {
                        var currentTab = getCurrentTab();
                        return (currentTab && currentTab.isLoading === true) || browserApp.updatingTabUrl;
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.sm
                    anchors.rightMargin: MSpacing.sm
                    spacing: MSpacing.xs

                    Rectangle {
                        Layout.preferredWidth: Constants.touchTargetSmall
                        Layout.preferredHeight: Constants.touchTargetSmall
                        Layout.alignment: Qt.AlignVCenter
                        color: "transparent"

                        Icon {
                            anchors.centerIn: parent
                            name: "arrow-left"
                            size: Constants.iconSizeSmall
                            color: {
                                var currentTab = getCurrentTab();
                                return (currentTab && currentTab.canGoBack) ? MColors.text : MColors.textTertiary;
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: {
                                if (currentTabIndex >= 0 && currentTabIndex < tabs.count) {
                                    var tab = tabs.get(currentTabIndex);
                                    return tab && tab.canGoBack === true;
                                }
                                return false;
                            }
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                HapticService.light();
                                var view = browserApp.currentWebView();
                                if (view && view.canGoBack)
                                    view.goBack();
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Constants.touchTargetSmall
                        Layout.preferredHeight: Constants.touchTargetSmall
                        Layout.alignment: Qt.AlignVCenter
                        color: "transparent"
                        visible: {
                            var currentTab = getCurrentTab();
                            return currentTab && currentTab.canGoForward;
                        }

                        Icon {
                            anchors.centerIn: parent
                            name: "arrow-right"
                            size: Constants.iconSizeSmall
                            color: MColors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                HapticService.light();
                                var view = browserApp.currentWebView();
                                if (view && view.canGoForward)
                                    view.goForward();
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height - MSpacing.sm * 2
                        Layout.alignment: Qt.AlignVCenter
                        radius: Constants.borderRadiusSmall
                        color: MColors.elevated
                        border.width: Constants.borderWidthThin
                        border.color: urlInput.activeFocus ? MColors.accent : MColors.border
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            propagateComposedEvents: true
                            onPressed: mouse => {
                                if (!urlInput.activeFocus)
                                    urlInput.forceActiveFocus();

                                mouse.accepted = false;
                            }
                        }

                        TextInput {
                            id: urlInput

                            property bool inlineCompletionActive: false
                            property string inlineTypedPrefix: ""
                            property bool suppressAutocompleteOnce: false
                            property bool lastEditWasDeletion: false
                            property bool applyingAutocomplete: false
                            property bool userTypedSinceFocus: false

                            anchors.left: parent.left
                            anchors.right: actionRow.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: MSpacing.md
                            anchors.rightMargin: MSpacing.xs
                            verticalAlignment: TextInput.AlignVCenter
                            color: MColors.text
                            font.pixelSize: MTypography.sizeBody
                            font.family: MTypography.fontFamily
                            selectByMouse: true
                            selectedTextColor: MColors.background
                            selectionColor: MColors.accent
                            clip: true
                            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    browserApp.isEditingAddress = true;
                                    browserApp.addressBarWantsFocus = false;
                                    urlInput.userTypedSinceFocus = false;
                                    var currentTab = getCurrentTab();
                                    urlInput.text = currentTab ? currentTab.url : "";
                                    selectAll();
                                    _clearAddressSuggestions();
                                } else {
                                    browserApp.isEditingAddress = false;
                                    urlInput.inlineCompletionActive = false;
                                    urlInput.inlineTypedPrefix = "";
                                    urlInput.userTypedSinceFocus = false;
                                    _clearAddressSuggestions();
                                }
                            }
                            Component.onCompleted: {
                                browserApp.urlInputRef = urlInput;
                                browserApp._syncAddressBarFromCurrentTab();
                                if (browserApp._pendingAddressBarFocus)
                                    browserApp.ensureAddressBarFocus(browserApp._pendingAddressBarSelectAll);
                            }
                            Component.onDestruction: {
                                if (browserApp.urlInputRef === urlInput)
                                    browserApp.urlInputRef = null;
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                                    urlInput.lastEditWasDeletion = true;
                                    if (urlInput.inlineCompletionActive && urlInput.text.startsWith(urlInput.inlineTypedPrefix)) {
                                        var expectedStart = urlInput.inlineTypedPrefix.length;
                                        if (selectionStart === expectedStart && selectionEnd === urlInput.text.length) {
                                            event.accepted = true;
                                            urlInput.suppressAutocompleteOnce = true;
                                            urlInput.applyingAutocomplete = true;
                                            urlInput.text = urlInput.inlineTypedPrefix;
                                            urlInput.cursorPosition = urlInput.inlineTypedPrefix.length;
                                            urlInput.deselect();
                                            urlInput.inlineCompletionActive = false;
                                            urlInput.applyingAutocomplete = false;
                                            _rebuildAddressSuggestions(urlInput.text);
                                            return;
                                        }
                                    }
                                    return;
                                }
                                urlInput.lastEditWasDeletion = false;
                                if (urlInput.inlineCompletionActive) {
                                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                                        event.accepted = true;
                                        urlInput.cursorPosition = urlInput.text.length;
                                        urlInput.deselect();
                                        urlInput.inlineCompletionActive = false;
                                        urlInput.inlineTypedPrefix = "";
                                        return;
                                    }
                                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) {
                                        event.accepted = true;
                                        urlInput.suppressAutocompleteOnce = true;
                                        urlInput.applyingAutocomplete = true;
                                        urlInput.text = urlInput.inlineTypedPrefix;
                                        urlInput.cursorPosition = urlInput.inlineTypedPrefix.length;
                                        urlInput.deselect();
                                        urlInput.inlineCompletionActive = false;
                                        urlInput.inlineTypedPrefix = "";
                                        urlInput.applyingAutocomplete = false;
                                        _rebuildAddressSuggestions(urlInput.text);
                                        return;
                                    }
                                }
                            }
                            onTextEdited: {
                                if (urlInput.applyingAutocomplete)
                                    return;

                                urlInput.userTypedSinceFocus = true;
                                _rebuildAddressSuggestions(text);
                                if (urlInput.suppressAutocompleteOnce) {
                                    urlInput.suppressAutocompleteOnce = false;
                                    return;
                                }
                                if (!activeFocus)
                                    return;

                                if (urlInput.lastEditWasDeletion)
                                    return;

                                if (cursorPosition !== text.length)
                                    return;

                                if (text.length < 2)
                                    return;

                                var match = findBestMatch(text);
                                if (match && match.length > text.length) {
                                    var currentPos = cursorPosition;
                                    urlInput.inlineTypedPrefix = text;
                                    urlInput.inlineCompletionActive = true;
                                    urlInput.applyingAutocomplete = true;
                                    urlInput.text = match;
                                    urlInput.select(currentPos, urlInput.text.length);
                                    urlInput.applyingAutocomplete = false;
                                }
                            }
                            onAccepted: {
                                focus = false;
                                urlInput.inlineCompletionActive = false;
                                urlInput.inlineTypedPrefix = "";
                                urlInput.userTypedSinceFocus = false;
                                _clearAddressSuggestions();
                                navigateTo(text);
                            }

                            Connections {
                                function onAppLaunched() {
                                    browserApp.ensureAddressBarFocus(true);
                                }

                                function onAppResumed() {
                                    browserApp.ensureAddressBarFocus(true);
                                }

                                function onTabsChanged() {
                                    if (!urlInput.activeFocus) {
                                        var currentTab = getCurrentTab();
                                        if (currentTab && currentTab.url !== urlInput.text)
                                            urlInput.text = currentTab.url;
                                    }
                                }

                                function onCurrentTabIndexChanged() {
                                    var currentTab = getCurrentTab();
                                    if (!urlInput.activeFocus)
                                        urlInput.text = currentTab ? currentTab.url : "";

                                    browserApp._syncAddressBarFromCurrentTab();
                                    if (currentTab && currentTab.isNewTab)
                                        browserApp.focusAddressBar(true);
                                }

                                target: browserApp
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !urlInput.text && !urlInput.activeFocus
                                text: isPrivateMode ? "Private Browsing" : "Search or enter URL"
                                color: MColors.textTertiary
                                font.pixelSize: MTypography.sizeBody
                                font.family: MTypography.fontFamily
                            }
                        }

                        Row {
                            id: actionRow

                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: MSpacing.xs
                            spacing: 0

                            Rectangle {
                                width: Constants.touchTargetSmall * 0.8
                                height: parent.height
                                color: "transparent"
                                visible: urlInput.text && urlInput.text.length > 0 && urlInput.activeFocus

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Constants.touchTargetSmall * 0.6
                                    height: Constants.touchTargetSmall * 0.6
                                    radius: width / 2
                                    color: clearMouseArea.pressed ? Qt.rgba(0.5, 0.5, 0.5, 0.3) : Qt.rgba(0.5, 0.5, 0.5, 0.15)

                                    Icon {
                                        anchors.centerIn: parent
                                        name: "x"
                                        size: Constants.iconSizeSmall * 0.6
                                        color: MColors.textSecondary
                                    }
                                }

                                MouseArea {
                                    id: clearMouseArea

                                    anchors.fill: parent
                                    onClicked: {
                                        HapticService.light();
                                        urlInput.text = "";
                                        urlInput.forceActiveFocus();
                                    }
                                }
                            }

                            Rectangle {
                                width: Constants.touchTargetSmall * 0.8
                                height: parent.height
                                color: "transparent"
                                visible: !urlInput.activeFocus
                                opacity: isPrivateMode ? 0.45 : 1

                                Icon {
                                    anchors.centerIn: parent
                                    name: "star"
                                    size: Constants.iconSizeSmall * 0.8
                                    color: {
                                        var currentTab = getCurrentTab();
                                        return (currentTab && isBookmarked(currentTab.url)) ? MColors.accent : MColors.textSecondary;
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        HapticService.light();
                                        if (isPrivateMode) {
                                            browserApp.showTransientMessage("Bookmarks are disabled in Private Browsing");
                                            return;
                                        }
                                        var currentTab = getCurrentTab();
                                        if (currentTab) {
                                            if (isBookmarked(currentTab.url))
                                                removeBookmark(currentTab.url);
                                            else
                                                addBookmark(currentTab.url, currentTab.title);
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: Constants.touchTargetSmall * 0.8
                                height: parent.height
                                color: "transparent"

                                Icon {
                                    anchors.centerIn: parent
                                    name: {
                                        var currentTab = getCurrentTab();
                                        return ((currentTab && currentTab.isLoading) || browserApp.updatingTabUrl) ? "x" : "refresh-cw";
                                    }
                                    size: Constants.iconSizeSmall * 0.8
                                    color: MColors.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        HapticService.light();
                                        var view = browserApp.currentWebView();
                                        if (!view) {
                                            Logger.warn("BrowserApp", "Refresh clicked but currentWebView() is null (tabIndex=" + currentTabIndex + ", tabs=" + tabs.count + ")");
                                            Qt.callLater(updateCurrentWebView);
                                            return;
                                        }
                                        Logger.warn("BrowserApp", "Refresh clicked url=" + view.url + " loading=" + view.loading + " lifecycle=" + view.lifecycleState);
                                        var currentTab = getCurrentTab();
                                        if (currentTab && currentTab.isLoading) {
                                            view.triggerWebAction(WebEngineView.Stop);
                                        } else {
                                            view.triggerWebAction(WebEngineView.ReloadAndBypassCache);
                                            view.reload();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: Constants.touchTargetSmall * 1.6
                        Layout.preferredHeight: Constants.touchTargetSmall
                        Layout.alignment: Qt.AlignVCenter
                        color: "transparent"

                        Row {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: -MSpacing.xs
                            spacing: 3

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "grid-3x3"
                                size: Constants.iconSizeSmall
                                color: MColors.text
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "(" + tabs.count + ")"
                                font.pixelSize: MTypography.sizeSmall * 0.85
                                font.weight: Font.Normal
                                color: MColors.textTertiary
                                visible: tabs.count > 0
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                HapticService.light();
                                if (isDrawerOpen)
                                    closeDrawer();
                                else
                                    openDrawer();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: addressSuggestionsPopup

            readonly property int rowHeight: Constants.touchTargetMedium
            readonly property int maxHeight: Math.min((parent.height - urlBar.height) * 0.45, rowHeight * 8)

            parent: rootContent
            z: 9000
            visible: urlInput.activeFocus && urlInput.userTypedSinceFocus && addressSuggestions.count > 0 && !isDrawerOpen && drawerProgress === 0
            color: MColors.bb10Elevated
            border.width: 1
            border.color: MColors.borderGlass
            radius: MRadius.md
            clip: true
            opacity: 0.98
            x: 0
            width: rootContent.width
            anchors.bottom: rootContent.bottom
            anchors.bottomMargin: urlBar.height
            height: Math.min(maxHeight, rowHeight * addressSuggestions.count)
            scale: visible ? 1 : 0.97
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: MColors.highlightSubtle
            }

            ListView {
                anchors.fill: parent
                anchors.margins: 2
                model: addressSuggestions
                interactive: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: ListView.view.width
                    height: addressSuggestionsPopup.rowHeight
                    radius: MRadius.sm
                    color: {
                        if (suggestionMouseArea.pressed)
                            return MColors.highlightMedium;

                        if (suggestionMouseArea.containsMouse)
                            return MColors.highlightSubtle;

                        return "transparent";
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: MSpacing.md
                        anchors.rightMargin: MSpacing.md
                        spacing: MSpacing.sm

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: Constants.iconSizeSmall
                            color: MColors.textSecondary
                            name: {
                                if (model.kind === "search")
                                    return "search";

                                if (model.kind === "bookmark")
                                    return "star";

                                if (model.kind === "history")
                                    return "history";

                                return "arrow-right";
                            }
                        }

                        Column {
                            readonly property var _parts: (model.display || "").split(" — ")
                            readonly property string primaryText: _parts.length > 0 ? _parts[0] : (model.display || "")
                            readonly property string secondaryText: _parts.length > 1 ? _parts.slice(1).join(" — ") : (model.kind === "search" ? "" : (model.value || ""))

                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (Constants.iconSizeSmall + MSpacing.sm)
                            spacing: 2

                            Text {
                                width: parent.width
                                text: parent.primaryText
                                color: MColors.textPrimary
                                font.pixelSize: MTypography.sizeBody
                                font.weight: MTypography.weightDemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: parent.secondaryText
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeSmall * 0.92
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                        visible: index < (addressSuggestions.count - 1)
                    }

                    MouseArea {
                        id: suggestionMouseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            HapticService.light();
                            urlInput.suppressAutocompleteOnce = true;
                            urlInput.inlineCompletionActive = false;
                            urlInput.inlineTypedPrefix = "";
                            var selectedValue = value;
                            var selectedKind = kind;
                            urlInput.text = selectedValue;
                            urlInput.cursorPosition = urlInput.text.length;
                            urlInput.focus = false;
                            urlInput.userTypedSinceFocus = false;
                            _clearAddressSuggestions();
                            navigateTo(selectedValue);
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: MMotion.xs
                        }
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.sm
                }
            }

            Behavior on scale {
                SpringAnimation {
                    spring: MMotion.springMedium
                    damping: MMotion.dampingMedium
                    epsilon: MMotion.epsilon
                }
            }

            layer.effect: DropShadow {
                horizontalOffset: 0
                verticalOffset: 4
                radius: 16
                samples: 33
                color: Qt.rgba(0, 0, 0, 0.6)
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: drawerProgress * 0.6
            visible: drawerProgress > 0

            MouseArea {
                anchors.fill: parent
                enabled: drawerProgress > 0
                onClicked: {
                    closeDrawer();
                }
            }
        }

        Item {
            id: drawerContainer

            width: parent.width * 0.85
            height: parent.height
            x: parent.width - (width * drawerProgress)
            visible: drawerProgress > 0 || isDragging
            clip: true

            BrowserDrawer {
                id: drawer

                anchors.fill: parent
                Component.onCompleted: {
                    browserApp.drawerRef = drawer;
                    if (drawer.tabsPage) {
                        drawer.tabsPage.tabs = Qt.binding(function () {
                            return browserApp.tabs;
                        });
                        drawer.tabsPage.currentTabId = Qt.binding(function () {
                            var currentTab = browserApp.getCurrentTab();
                            return currentTab ? currentTab.tabId : -1;
                        });
                    }
                    if (drawer.bookmarksPage)
                        drawer.bookmarksPage.bookmarks = Qt.binding(function () {
                            return browserApp.bookmarks;
                        });

                    if (drawer.historyPage)
                        drawer.historyPage.history = Qt.binding(function () {
                            return browserApp.history;
                        });

                    if (drawer.settingsPage) {
                        drawer.settingsPage.searchEngine = Qt.binding(function () {
                            return browserApp.searchEngineName;
                        });
                        drawer.settingsPage.searchEngineUrl = Qt.binding(function () {
                            return browserApp.searchEngineUrl;
                        });
                        drawer.settingsPage.homepage = Qt.binding(function () {
                            return browserApp.homepageUrl;
                        });
                        drawer.settingsPage.isPrivateMode = Qt.binding(function () {
                            return browserApp.isPrivateMode;
                        });
                        drawer.settingsPage.isPrivateModeChanged.connect(function () {
                            browserApp.setPrivateMode(drawer.settingsPage.isPrivateMode);
                        });
                        drawer.settingsPage.searchEngineChanged.connect(function () {
                            if (browserApp.searchEngineName !== drawer.settingsPage.searchEngine) {
                                browserApp.searchEngineName = drawer.settingsPage.searchEngine;
                                saveSettings();
                            }
                        });
                        drawer.settingsPage.searchEngineUrlChanged.connect(function () {
                            if (browserApp.searchEngineUrl !== drawer.settingsPage.searchEngineUrl) {
                                browserApp.searchEngineUrl = drawer.settingsPage.searchEngineUrl;
                                saveSettings();
                            }
                        });
                        drawer.settingsPage.homepageChanged.connect(function () {
                            if (browserApp.homepageUrl !== drawer.settingsPage.homepage) {
                                browserApp.homepageUrl = drawer.settingsPage.homepage;
                                saveSettings();
                            }
                        });
                    }
                }
                onClosed: {
                    closeDrawer();
                }
                onTabSelected: tabId => {
                    switchToTab(tabId);
                    closeDrawer();
                }
                onNewTabRequested: {
                    var tabId = createNewTab();
                    if (tabId >= 0)
                        closeDrawer();
                }
                onBookmarkSelected: url => {
                    navigateTo(url);
                }
                onHistorySelected: url => {
                    navigateTo(url);
                }

                Connections {
                    function onCloseTab(tabId) {
                        browserApp.closeTab(tabId);
                    }

                    target: drawer.tabsPage
                }

                Connections {
                    function onDeleteBookmark(url) {
                        browserApp.removeBookmark(url);
                    }

                    target: drawer.bookmarksPage
                }

                Connections {
                    function onClearHistory() {
                        browserApp.clearHistory();
                    }

                    target: drawer.historyPage
                }

                Connections {
                    function onClearHistoryRequested() {
                        if (!browserApp.isPrivateMode)
                            browserApp.clearHistory();
                    }

                    function onClearCookiesRequested() {
                        var view = browserApp.currentWebView();
                        if (view && view.profile) {
                            var ok = BrowserData.clearCookiesAndCache(view.profile);
                            if (ok)
                                Logger.info("BrowserApp", "Cleared cookies and HTTP cache");
                            else
                                Logger.warn("BrowserApp", "Failed to clear cookies/cache (invalid profile object)");
                        } else {
                            Logger.warn("BrowserApp", "No active web profile to clear");
                        }
                    }

                    target: drawer.settingsPage
                }
            }

            Behavior on x {
                enabled: !isDragging

                NumberAnimation {
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
