import QtQuick
import QtWebEngine
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonUI.Core
import QtQuick.Layouts
import "components"

MApp {
    id: browserApp
    appId: "browser"
    appName: "Browser"
    appIcon: "assets/icon.svg"

    property alias tabs: tabsModel
    property int currentTabIndex: 0
    property int nextTabId: 1
    readonly property int maxTabs: 20

    property var backConnection: null
    property var forwardConnection: null

    property var bookmarks: []
    property var history: []

    ListModel {
        id: tabsModel
    }

    property bool isPrivateMode: false

    property real drawerProgress: 0
    property bool isDrawerOpen: false
    property bool isDragging: false

    // Reference to drawer component (set after drawer is created)
    property var drawerRef: null

    property var lastLoadedUrl: ""
    property int consecutiveLoadAttempts: 0
    property var lastLoadTime: 0
    readonly property int maxConsecutiveLoads: 3
    readonly property int loadCooldownMs: 2000

    property var webView: null
    property bool updatingTabUrl: false

    // Search Engine Settings
    property string searchEngineName: "DuckDuckGo"
    property string searchEngineUrl: "https://duckduckgo.com/?q="
    property string homepageUrl: "https://duckduckgo.com"

    onCurrentTabIndexChanged: {
        Qt.callLater(updateCurrentWebView);
    }

    function updateCurrentWebView() {
        // webViewStack is defined later, but we can access it by id if it's in scope
        // However, accessing children of StackLayout/Repeater dynamically can be tricky.
        // The Repeater creates items. StackLayout manages them.
        // webViewStack.children[i] corresponds to the item created by Repeater.
        
        if (typeof webViewStack !== "undefined" && webViewStack.children.length > currentTabIndex && currentTabIndex >= 0) {
             // The children of StackLayout include the Repeater (which is not a visual item in the layout sense usually, but here it creates children)
             // Actually, Repeater inside StackLayout adds its delegates as children of StackLayout.
             // So webViewStack.children[currentTabIndex] should be the WebEngineView.
             webView = webViewStack.children[currentTabIndex];
        } else {
             webView = null;
        }
    }

    onAppLaunched: {
        Logger.warn("Browser", " onAppLaunched");
    }

    onAppResumed: {
        Logger.warn("Browser", "Browser app resumed");
    }

    Component.onCompleted: {
        Logger.info("BrowserApp", "Initializing browser...");
        loadSettings();
        loadBookmarks();
        loadHistory();
        loadTabs();

        if (tabs.count === 0) {
            Logger.info("BrowserApp", "No tabs found, creating default tab");
            createNewTab();
        }
        
        // Defer to ensure children are created
        Qt.callLater(updateCurrentWebView);
    }

    function handleBack() {
        if (isDrawerOpen) {
            closeDrawer();
            return true;
        }

        if (webView && webView.canGoBack) {
            webView.goBack();
            return true;
        }

        // Default behavior (minimize)
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
            url: url,
            title: title || url,
            timestamp: Date.now()
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
            if (bookmarks[i].url === url) {
                return true;
            }
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
            url: url,
            title: title || url,
            timestamp: now,
            visitCount: 1
        };

        newHistory.unshift(historyItem);

        if (newHistory.length > 100) {
            newHistory = newHistory.slice(0, 100);
        }

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
                            // Ensure all required properties are present
                            tabs.append({
                                tabId: tab.id,
                                url: (tab.url && tab.url !== "about:blank") ? tab.url : homepageUrl,
                                title: tab.title || "New Tab",
                                isLoading: false,
                                canGoBack: false,
                                canGoForward: false,
                                loadProgress: 0
                            });
                            if (tab.id > maxId) {
                                maxId = tab.id;
                            }
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
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var tabsArray = [];
            for (var i = 0; i < tabs.count; i++) {
                var tab = tabs.get(i);
                tabsArray.push({
                    id: tab.tabId,
                    url: tab.url,
                    title: tab.title
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
            tabId: nextTabId++,
            url: url || homepageUrl,
            title: "New Tab",
            isLoading: false,
            canGoBack: false,
            canGoForward: false,
            loadProgress: 0
        };

        tabs.append(newTab);
        saveTabs();

        Logger.info("BrowserApp", "Created new tab: " + newTab.tabId);
        switchToTab(newTab.tabId);
        return newTab.tabId;
    }

    function closeTab(tabId) {
        for (var i = 0; i < tabs.count; i++) {
            if (tabs.get(i).tabId === tabId) {
                var wasCurrent = (i === currentTabIndex);
                
                // Safely stop the WebEngineView before removal to prevent crashes
                if (typeof webViewStack !== "undefined" && webViewStack.children.length > i) {
                    var viewToRemove = webViewStack.children[i];
                    if (viewToRemove) {
                        try {
                            viewToRemove.stop();
                            viewToRemove.url = "about:blank";
                        } catch (e) {
                            Logger.warn("BrowserApp", "Error stopping view: " + e);
                        }
                    }
                }

                // If closing the current tab, clear the webView reference first to avoid crashes
                if (wasCurrent) {
                    webView = null;
                }

                tabs.remove(i);

                if (tabs.count === 0) {
                    createNewTab();
                } else {
                    // Adjust index if we closed a tab before the current one
                    if (i < currentTabIndex) {
                        currentTabIndex--;
                    }
                    // Clamp index
                    if (currentTabIndex >= tabs.count) {
                        currentTabIndex = tabs.count - 1;
                    }
                    
                    // Force update of webView if we closed the current tab
                    if (wasCurrent) {
                        Qt.callLater(updateCurrentWebView);
                    }
                }
                
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
        if (currentTabIndex >= 0 && currentTabIndex < tabs.count) {
            return tabs.get(currentTabIndex);
        }
        return null;
    }

    function findBestMatch(partialText) {
        if (!partialText || partialText.length < 2)
            return "";

        partialText = partialText.toLowerCase();

        // Search Bookmarks first (higher priority)
        for (var i = 0; i < bookmarks.length; i++) {
            var url = bookmarks[i].url.toLowerCase();
            // Strip protocol for matching
            var cleanUrl = url.replace("https://", "").replace("http://", "").replace("www.", "");
            if (cleanUrl.startsWith(partialText)) {
                return cleanUrl;
            }
        }

        // Search History
        for (var j = 0; j < history.length; j++) {
            var hUrl = history[j].url.toLowerCase();
            var hCleanUrl = hUrl.replace("https://", "").replace("http://", "").replace("www.", "");
            if (hCleanUrl.startsWith(partialText)) {
                return hCleanUrl;
            }
        }

        return "";
    }

    function navigateTo(url) {
        Logger.warn("Browser", "navigateTo called with: " + url);
        if (!url)
            return;

        var lowerUrl = url.toLowerCase().trim();
        if (lowerUrl.startsWith("javascript:") || lowerUrl.startsWith("data:") || lowerUrl.startsWith("file:")) {
            Logger.warn("BrowserApp", "Blocked dangerous URI scheme: " + lowerUrl.split(":")[0]);
            return;
        }

        var finalUrl = url;
        if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("about:")) {
            if (url.includes(".") && !url.includes(" ")) {
                finalUrl = "https://" + url;
            } else {
                finalUrl = searchEngineUrl + encodeURIComponent(url);
            }
        }

        updatingTabUrl = true;
        tabs.setProperty(currentTabIndex, "url", finalUrl);
        tabs.setProperty(currentTabIndex, "isLoading", true);
        tabs.setProperty(currentTabIndex, "loadProgress", 10);
        updatingTabUrl = false;
    }

    property string pendingUrl: ""

    Timer {
        id: cleanupTimer
        interval: 300 // Increased to 300ms for better stability
        repeat: false
        onTriggered: {
            if (webView && pendingUrl) {
                Logger.warn("Browser", "Executing delayed navigation to: " + pendingUrl);
                gc(); // Force Garbage Collection before new load
                webView.url = pendingUrl;
                Qt.callLater(function () {
                    updatingTabUrl = false;
                });
            }
        }
    }

    function openDrawer() {
        isDrawerOpen = true;
        drawerProgress = 1.0;
    }

    function closeDrawer() {
        isDrawerOpen = false;
        drawerProgress = 0;
    }

    content: Rectangle {
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
                        model: tabs

                        WebEngineView {
                            id: webView

                            // Bind URL to model using model.url
                            url: model.url

                            zoomFactor: 1.0

                            // Use default profile for stability
                            // profile.httpUserAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

                            settings.accelerated2dCanvasEnabled: false
                            settings.webGLEnabled: false
                            settings.pluginsEnabled: false
                            settings.fullScreenSupportEnabled: true
                            settings.allowRunningInsecureContent: false
                            settings.javascriptEnabled: true
                            settings.javascriptCanOpenWindows: false
                            settings.javascriptCanAccessClipboard: false
                            settings.localStorageEnabled: !isPrivateMode
                            settings.localContentCanAccessRemoteUrls: false
                            settings.spatialNavigationEnabled: false
                            settings.touchIconsEnabled: false
                            settings.focusOnNavigationEnabled: true
                            settings.playbackRequiresUserGesture: true
                            settings.webRTCPublicInterfacesOnly: true
                            settings.dnsPrefetchEnabled: false
                            settings.showScrollBars: false

                            // Use NoCache for maximum stability (prevents OOM)
                            profile.httpCacheType: WebEngineProfile.NoCache
                            profile.persistentCookiesPolicy: WebEngineProfile.NoPersistentCookies

                            // Handle render process crashes gracefully
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

                                // Try to reload or show error
                                if (terminationStatus !== WebEngineView.NormalTerminationStatus) {
                                    Logger.warn("Browser", "Reloading due to crash...");
                                    Qt.callLater(function () {
                                        webView.reload();
                                    });
                                }
                            }

                            onUrlChanged: {
                                if (updatingTabUrl)
                                    return;

                                // Update model when URL changes (navigation)
                                if (index >= 0 && index < tabs.count) {
                                    if (tabs.get(index).url !== url.toString()) {
                                        tabs.setProperty(index, "url", url.toString());
                                    }
                                }
                            }

                            onTitleChanged: {
                                if (index >= 0 && index < tabs.count) {
                                    if (tabs.get(index).title !== title) {
                                        tabs.setProperty(index, "title", title);

                                        if (!isPrivateMode) {
                                            addToHistory(url.toString(), title);
                                        }
                                    }
                                }
                            }

                            onLoadingChanged: function (loadRequest) {
                                if (index >= 0 && index < tabs.count) {
                                    var isLoading = (loadRequest.status === WebEngineView.LoadStartedStatus);
                                    tabs.setProperty(index, "isLoading", isLoading);

                                    if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                                        tabs.setProperty(index, "title", title);
                                        if (!isPrivateMode) {
                                            addToHistory(url.toString(), title);
                                        }
                                        consecutiveLoadAttempts = 0;
                                    }

                                    if (loadRequest.status === WebEngineView.LoadFailedStatus)
                                    // Handle failure
                                    {}
                                }
                            }

                            onCanGoBackChanged: {
                                if (index >= 0 && index < tabs.count) {
                                    if (tabs.get(index).canGoBack !== canGoBack) {
                                        tabs.setProperty(index, "canGoBack", canGoBack);
                                    }
                                }
                            }

                            onCanGoForwardChanged: {
                                if (index >= 0 && index < tabs.count) {
                                    if (tabs.get(index).canGoForward !== canGoForward) {
                                        tabs.setProperty(index, "canGoForward", canGoForward);
                                    }
                                }
                            }

                            onLoadProgressChanged: {
                                if (index >= 0 && index < tabs.count) {
                                    if (tabs.get(index).loadProgress !== loadProgress) {
                                        tabs.setProperty(index, "loadProgress", loadProgress);
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: rightEdgeGesture
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Constants.gestureEdgeWidth
                    z: 1000

                    property real startX: 0
                    property real currentX: 0

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
                        if (drawerProgress > 0.3) {
                            openDrawer();
                        } else {
                            closeDrawer();
                        }
                    }
                }
            }

            Rectangle {
                id: urlBar
                width: parent.width
                height: Constants.touchTargetMedium + MSpacing.sm
                color: isPrivateMode ? Qt.rgba(0.5, 0, 0.5, 0.3) : MColors.surface

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
                            return parent.width * 0.2; // Fake 20% progress during preparation

                        var currentTab = getCurrentTab();
                        if (currentTab && currentTab.isLoading && currentTab.loadProgress) {
                            return parent.width * (currentTab.loadProgress / 100);
                        }
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

                    // Back Button
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
                                if (webView && webView.canGoBack) {
                                    webView.goBack();
                                }
                            }
                        }
                    }

                    // Forward Button
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
                                if (webView && webView.canGoForward) {
                                    webView.goForward();
                                }
                            }
                        }
                    }

                    // Address Bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height - MSpacing.sm * 2
                        Layout.alignment: Qt.AlignVCenter
                        radius: Constants.borderRadiusSmall
                        color: MColors.elevated
                        border.width: Constants.borderWidthThin
                        border.color: urlInput.activeFocus ? MColors.accent : MColors.border
                        clip: true

                        TextInput {
                            id: urlInput
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
                            text: {
                                var currentTab = getCurrentTab();
                                return currentTab ? currentTab.url : "";
                            }

                            Connections {
                                target: browserApp
                                function onAppLaunched() {
                                    Qt.callLater(function () {
                                        urlInput.focus = true;
                                        urlInput.selectAll();
                                    });
                                }
                                function onAppResumed() {
                                    Qt.callLater(function () {
                                        urlInput.focus = true;
                                        urlInput.selectAll();
                                    });
                                }
                                // Fix: Restore binding when tabs change (navigation)
                                function onTabsChanged() {
                                    if (!urlInput.activeFocus) {
                                        var currentTab = getCurrentTab();
                                        if (currentTab && currentTab.url !== urlInput.text) {
                                            urlInput.text = currentTab.url;
                                        }
                                    }
                                }
                                function onCurrentTabIndexChanged() {
                                    var currentTab = getCurrentTab();
                                    if (currentTab) {
                                        urlInput.text = currentTab.url;
                                    }
                                }
                            }

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    selectAll();
                                }
                            }

                            onTextEdited: {
                                // Inline Autocomplete
                                if (text.length >= 2) {
                                    var match = findBestMatch(text);
                                    if (match && match.length > text.length) {
                                        var currentPos = cursorPosition;
                                        var typedText = text;

                                        // Append the rest of the match
                                        text = match;

                                        // Select the suggested part so typing replaces it
                                        select(currentPos, text.length);
                                    }
                                }
                            }

                            onAccepted: {
                                focus = false;
                                navigateTo(text);
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

                        // Actions inside Address Bar
                        Row {
                            id: actionRow
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: MSpacing.xs
                            spacing: 0

                            // Clear Button
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
                                        urlInput.focus = true;
                                    }
                                }
                            }

                            // Star Button
                            Rectangle {
                                width: Constants.touchTargetSmall * 0.8
                                height: parent.height
                                color: "transparent"
                                visible: !urlInput.activeFocus

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
                                        var currentTab = getCurrentTab();
                                        if (currentTab) {
                                            if (isBookmarked(currentTab.url)) {
                                                removeBookmark(currentTab.url);
                                            } else {
                                                addBookmark(currentTab.url, currentTab.title);
                                            }
                                        }
                                    }
                                }
                            }

                            // Refresh/Stop Button
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
                                        if (webView) {
                                            var currentTab = getCurrentTab();
                                            if (currentTab && currentTab.isLoading) {
                                                webView.stop();
                                            } else {
                                                webView.reload();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Tabs Button
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
                                name: "grid"
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
                                if (isDrawerOpen) {
                                    closeDrawer();
                                } else {
                                    openDrawer();
                                }
                            }
                        }
                    }
                }
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

            Behavior on x {
                enabled: !isDragging
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }

            BrowserDrawer {
                id: drawer
                anchors.fill: parent

                Component.onCompleted: {
                    // Store reference for safe access from other components
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

                    if (drawer.bookmarksPage) {
                        drawer.bookmarksPage.bookmarks = Qt.binding(function () {
                            return browserApp.bookmarks;
                        });
                    }

                    if (drawer.historyPage) {
                        drawer.historyPage.history = Qt.binding(function () {
                            return browserApp.history;
                        });
                    }

                    if (drawer.settingsPage) {
                        // Bind settings page to app properties
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
                            browserApp.isPrivateMode = drawer.settingsPage.isPrivateMode;
                        });

                        drawer.settingsPage.searchEngineChanged.connect(function () {
                            // Only update if changed from UI
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
                    if (tabId >= 0) {
                        closeDrawer();
                    }
                }

                onBookmarkSelected: url => {
                    navigateTo(url);
                }

                onHistorySelected: url => {
                    navigateTo(url);
                }

                Connections {
                    target: drawer.tabsPage
                    function onCloseTab(tabId) {
                        browserApp.closeTab(tabId);
                    }
                }

                Connections {
                    target: drawer.bookmarksPage
                    function onDeleteBookmark(url) {
                        browserApp.removeBookmark(url);
                    }
                }

                Connections {
                    target: drawer.historyPage
                    function onClearHistory() {
                        browserApp.clearHistory();
                    }
                }

                Connections {
                    target: drawer.settingsPage
                    function onClearHistoryRequested() {
                        if (!browserApp.isPrivateMode) {
                            browserApp.clearHistory();
                        }
                    }

                    function onClearCookiesRequested() {
                        if (webView && webView.profile) {
                            webView.profile.clearAllVisitedLinks();
                            Logger.info("BrowserApp", "Cleared cookies and site data");
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: NavigationRouter
        function onDeepLinkRequested(appId, route, params) {
            if (appId === "browser") {
                Logger.info("BrowserApp", "Deep link requested with params: " + JSON.stringify(params));

                // Handle URL parameter
                if (params && params.url) {
                    Logger.info("BrowserApp", "Opening URL from deep link: " + params.url);
                    navigateTo(params.url);
                }
            }
        }
    }

    onAppPaused: {
        saveTabs();
        saveBookmarks();
        saveHistory();
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
        if (backConnection) {
            browserApp.backPressed.disconnect(backConnection);
            backConnection = null;
        }

        if (forwardConnection) {
            browserApp.forwardPressed.disconnect(forwardConnection);
            forwardConnection = null;
        }

        if (webView) {
            webView.stop();
            webView.url = "about:blank";
            webView = null;
        }
    }
}
