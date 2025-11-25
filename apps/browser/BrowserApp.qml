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
    
    property var tabs: []
    property int currentTabIndex: 0
    property int nextTabId: 1
    readonly property int maxTabs: 20
    
    property var backConnection: null
    property var forwardConnection: null
    
    property var bookmarks: []
    property var history: []
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
    
    onAppLaunched: {
        Logger.warn("Browser", " onAppLaunched")
    }
    
    onAppResumed: {
        Logger.warn("Browser", "Browser app resumed")
    }

    function loadBookmarks() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var savedBookmarks = SettingsManagerCpp.get("browser/bookmarks", "[]")
            try {
                bookmarks = JSON.parse(savedBookmarks)
            } catch (e) {
                Logger.error("BrowserApp", "Failed to load bookmarks: " + e)
                bookmarks = []
            }
        } else {
            bookmarks = []
        }
    }
    
    function saveBookmarks() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var data = JSON.stringify(bookmarks)
            SettingsManagerCpp.set("browser/bookmarks", data)
        }
    }
    
    function addBookmark(url, title) {
        for (var i = 0; i < bookmarks.length; i++) {
            if (bookmarks[i].url === url) {
                Logger.info("BrowserApp", "Bookmark already exists")
                return false
            }
        }
        
        var bookmark = {
            url: url,
            title: title || url,
            timestamp: Date.now()
        }
        
        var newBookmarks = bookmarks.slice()
        newBookmarks.push(bookmark)
        bookmarks = newBookmarks
        bookmarksChanged()
        saveBookmarks()
        Logger.info("BrowserApp", "Added bookmark: " + title)
        return true
    }
    
    function removeBookmark(url) {
        for (var i = 0; i < bookmarks.length; i++) {
            if (bookmarks[i].url === url) {
                var newBookmarks = bookmarks.slice()
                newBookmarks.splice(i, 1)
                bookmarks = newBookmarks
                bookmarksChanged()
                saveBookmarks()
                return true
            }
        }
        return false
    }
    
    function isBookmarked(url) {
        for (var i = 0; i < bookmarks.length; i++) {
            if (bookmarks[i].url === url) {
                return true
            }
        }
        return false
    }
    
    function loadHistory() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var savedHistory = SettingsManagerCpp.get("browser/history", "[]")
            try {
                history = JSON.parse(savedHistory)
            } catch (e) {
                Logger.error("BrowserApp", "Failed to load history: " + e)
                history = []
            }
        } else {
            history = []
        }
    }
    
    function saveHistory() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var data = JSON.stringify(history)
            SettingsManagerCpp.set("browser/history", data)
        }
    }
    
    function addToHistory(url, title) {
        if (isPrivateMode) return
        
        var now = Date.now()
        var newHistory = history.slice()
        
        for (var i = 0; i < newHistory.length; i++) {
            if (newHistory[i].url === url) {
                newHistory[i].timestamp = now
                newHistory[i].visitCount = (newHistory[i].visitCount || 1) + 1
                newHistory[i].title = title || newHistory[i].title
                history = newHistory
                historyChanged()
                saveHistory()
                return
            }
        }
        
        var historyItem = {
            url: url,
            title: title || url,
            timestamp: now,
            visitCount: 1
        }
        
        newHistory.unshift(historyItem)
        
        if (newHistory.length > 100) {
            newHistory = newHistory.slice(0, 100)
        }
        
        history = newHistory
        historyChanged()
        saveHistory()
    }
    
    function clearHistory() {
        history = []
        historyChanged()
        saveHistory()
        Logger.info("BrowserApp", "History cleared")
    }
    
    function loadTabs() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var savedTabs = SettingsManagerCpp.get("browser/tabs", "[]")
            var defaultUrl = SettingsManagerCpp.get("browser/homepage", "https://duckduckgo.com")
            
            try {
                var loadedTabs = JSON.parse(savedTabs)
                if (loadedTabs.length > 0) {
                    var normalizedTabs = loadedTabs.map(function(tab) {
                        return {
                            id: tab.id,
                            url: (tab.url && tab.url !== "about:blank") ? tab.url : defaultUrl,
                            title: tab.title || "New Tab",
                            isLoading: false,
                            canGoBack: false,
                            canGoForward: false,
                            loadProgress: 0
                        }
                    })
                    tabs = normalizedTabs
                    nextTabId = Math.max(...tabs.map(t => t.id)) + 1
                }
            } catch (e) {
                Logger.error("BrowserApp", "Failed to load tabs: " + e)
            }
        }
    }
    
    function saveTabs() {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp) {
            var tabsData = tabs.map(function(tab) {
                return {
                    id: tab.id,
                    url: tab.url,
                    title: tab.title
                }
            })
            var data = JSON.stringify(tabsData)
            SettingsManagerCpp.set("browser/tabs", data)
        }
    }
    
    function createNewTab(url) {
        if (tabs.length >= maxTabs) {
            Logger.warn("BrowserApp", "Maximum tabs (" + maxTabs + ") reached")
            return -1
        }
        
        var defaultUrl = drawerRef && drawerRef.settingsPage ? drawerRef.settingsPage.homepage : "https://duckduckgo.com"
        
        var newTab = {
            id: nextTabId++,
            url: url || defaultUrl,
            title: "New Tab",
            isLoading: false,
            canGoBack: false,
            canGoForward: false,
            loadProgress: 0
        }
        
        var newTabs = tabs.slice()
        newTabs.push(newTab)
        tabs = newTabs
        tabsChanged()
        currentTabIndex = tabs.length - 1
        saveTabs()
        
        Logger.info("BrowserApp", "Created new tab: " + newTab.id)
        return newTab.id
    }
    
    function closeTab(tabId) {
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].id === tabId) {
                var newTabs = tabs.slice()
                newTabs.splice(i, 1)
                tabs = newTabs
                tabsChanged()
                
                if (tabs.length === 0) {
                    createNewTab()
                } else if (currentTabIndex >= tabs.length) {
                    currentTabIndex = tabs.length - 1
                }
                
                saveTabs()
                Logger.info("BrowserApp", "Closed tab: " + tabId)
                return
            }
        }
    }
    
    function switchToTab(tabId) {
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].id === tabId) {
                currentTabIndex = i
                Logger.info("BrowserApp", "Switched to tab: " + tabId)
                return
            }
        }
    }
    
    function getCurrentTab() {
        if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
            return tabs[currentTabIndex]
        }
        return null
    }
    
    function navigateTo(url) {
        Logger.warn("Browser", "navigateTo called with: " + url)
        if (!url) return
        
        var lowerUrl = url.toLowerCase().trim()
        if (lowerUrl.startsWith("javascript:") || lowerUrl.startsWith("data:") || 
            lowerUrl.startsWith("file:")) {
            Logger.warn("BrowserApp", "Blocked dangerous URI scheme: " + lowerUrl.split(":")[0])
            return
        }
        
        if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("about:")) {
            if (url.includes(".") && !url.includes(" ")) {
                url = "https://" + url
            } else {
                var searchEngineUrl = (drawerRef && drawerRef.settingsPage) ? drawerRef.settingsPage.searchEngineUrl : "https://www.google.com/search?q="
                url = searchEngineUrl + encodeURIComponent(url)
            }
        }
        
        var currentTime = Date.now()
        
        if (url === lastLoadedUrl) {
            consecutiveLoadAttempts++
            
            if (consecutiveLoadAttempts >= maxConsecutiveLoads) {
                if ((currentTime - lastLoadTime) < loadCooldownMs) {
                    Logger.warn("BrowserApp", "THROTTLED: Too many requests to " + url + " (attempt " + consecutiveLoadAttempts + "). Blocking for " + loadCooldownMs + "ms.")
                    return
                } else {
                    Logger.info("BrowserApp", "Cooldown period elapsed, resetting throttle counter")
                    consecutiveLoadAttempts = 0
                }
            }
        } else {
            consecutiveLoadAttempts = 1
        }
        
        lastLoadedUrl = url
        lastLoadTime = currentTime
        
        var currentTab = getCurrentTab()
        if (currentTab && currentTabIndex >= 0 && currentTabIndex < tabs.length) {
            if (webView) {
                Logger.warn("Browser", "Setting webView.url to: " + url)
                updatingTabUrl = true
                webView.url = url
                Qt.callLater(function() {
                    updatingTabUrl = false
                })
            } else {
                Logger.warn("Browser", "ERROR: webView is null, cannot navigate")
            }
            
            var newTabs = tabs.slice()
            newTabs[currentTabIndex] = Object.assign({}, currentTab, {
                url: url,
                isLoading: true
            })
            tabs = newTabs
            tabsChanged()
        }
    }
    
    function openDrawer() {
        isDrawerOpen = true
        drawerProgress = 1.0
    }
    
    function closeDrawer() {
        isDrawerOpen = false
        drawerProgress = 0
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
                
                Component {
                    id: webEngineComponent
                    WebEngineView {
                        anchors.fill: parent
                        
                        zoomFactor: 1.0
                        
                        profile.httpUserAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                        
                        settings.accelerated2dCanvasEnabled: true
                        settings.webGLEnabled: true
                        settings.pluginsEnabled: true
                        settings.fullScreenSupportEnabled: true
                        settings.allowRunningInsecureContent: false
                        settings.javascriptEnabled: true
                        settings.javascriptCanOpenWindows: false
                        settings.javascriptCanAccessClipboard: false
                        settings.localStorageEnabled: !isPrivateMode
                        settings.localContentCanAccessRemoteUrls: false
                        settings.spatialNavigationEnabled: false
                        settings.touchIconsEnabled: true
                        settings.focusOnNavigationEnabled: true
                        settings.playbackRequiresUserGesture: false
                        settings.webRTCPublicInterfacesOnly: true
                        settings.dnsPrefetchEnabled: true
                        settings.showScrollBars: false
                            
                        onUrlChanged: {
                            if (updatingTabUrl) {
                                Logger.warn("Browser", "onUrlChanged BLOCKED by updatingTabUrl flag")
                                return
                            }
                            
                            Logger.warn("Browser", "onUrlChanged: " + url.toString())
                            
                            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                var currentTab = tabs[currentTabIndex]
                                if (currentTab && currentTab.url !== url.toString()) {
                                    var newTabs = tabs.slice()
                                    newTabs[currentTabIndex] = Object.assign({}, currentTab, {
                                        url: url.toString()
                                    })
                                    tabs = newTabs
                                }
                            }
                        }
                        
                        onTitleChanged: {
                            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                var currentTab = tabs[currentTabIndex]
                                if (currentTab && currentTab.title !== title) {
                                    var newTabs = tabs.slice()
                                    newTabs[currentTabIndex] = Object.assign({}, currentTab, {
                                        title: title
                                    })
                                    tabs = newTabs
                                    
                                    if (!isPrivateMode) {
                                        addToHistory(url.toString(), title)
                                    }
                                }
                            }
                        }
                        
                        onLoadingChanged: function(loadRequest) {
                            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                var currentTab = tabs[currentTabIndex]
                                if (!currentTab) return
                                
                                var updates = {
                                    isLoading: (loadRequest.status === WebEngineView.LoadStartedStatus)
                                }
                                
                                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                                    updates.title = title
                                    if (!isPrivateMode) {
                                        addToHistory(url.toString(), title)
                                    }
                                    consecutiveLoadAttempts = 0
                                    
                                    runJavaScript(`
                                        (function() {
                                            var meta = document.querySelector('meta[name="viewport"]');
                                            if (!meta) {
                                                meta = document.createElement('meta');
                                                meta.name = 'viewport';
                                                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
                                                document.getElementsByTagName('head')[0].appendChild(meta);
                                            }
                                            document.body.style.maxWidth = '100vw';
                                            document.body.style.overflowX = 'hidden';
                                            document.documentElement.style.maxWidth = '100vw';
                                            document.documentElement.style.overflowX = 'hidden';
                                        })();
                                    `)
                                }
                                
                                if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                                    Logger.error("Browser", "Load failed: " + loadRequest.errorString)
                                    
                                    if (url.toString() === lastLoadedUrl) {
                                        consecutiveLoadAttempts++
                                        if (consecutiveLoadAttempts >= maxConsecutiveLoads) {
                                            Logger.warn("Browser", "STOPPING: Failed to load " + url.toString() + " " + consecutiveLoadAttempts + " times.")
                                            updatingTabUrl = true
                                            url = "about:blank"
                                            updates.url = "about:blank"
                                            updates.isLoading = false
                                            Qt.callLater(function() {
                                                updatingTabUrl = false
                                            })
                                        }
                                    }
                                }
                                
                                var newTabs = tabs.slice()
                                newTabs[currentTabIndex] = Object.assign({}, currentTab, updates)
                                tabs = newTabs
                            }
                        }
                        
                        onCanGoBackChanged: {
                            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                var currentTab = tabs[currentTabIndex]
                                if (currentTab && currentTab.canGoBack !== canGoBack) {
                                    var newTabs = tabs.slice()
                                    newTabs[currentTabIndex] = Object.assign({}, currentTab, {
                                        canGoBack: canGoBack
                                    })
                                    tabs = newTabs
                                    updateNavigationDepth()
                                }
                            }
                        }
                        
                        onCanGoForwardChanged: {
                            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                var currentTab = tabs[currentTabIndex]
                                if (currentTab && currentTab.canGoForward !== canGoForward) {
                                    var newTabs = tabs.slice()
                                    newTabs[currentTabIndex] = Object.assign({}, currentTab, {
                                        canGoForward: canGoForward
                                    })
                                    tabs = newTabs
                                    updateNavigationDepth()
                                }
                            }
                        }
                        
                        onLoadProgressChanged: {
                            if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                var currentTab = tabs[currentTabIndex]
                                if (currentTab && currentTab.loadProgress !== loadProgress) {
                                    var newTabs = tabs.slice()
                                    newTabs[currentTabIndex] = Object.assign({}, currentTab, {
                                        loadProgress: loadProgress
                                    })
                                    tabs = newTabs
                                }
                            }
                        }
                        
                        Component.onCompleted: {
                            browserApp.webView = this
                            Logger.warn("Browser", "WebEngineView created and assigned")
                            
                            Qt.callLater(function() {
                                if (tabs.length > 0 && currentTabIndex >= 0 && tabs[currentTabIndex].url) {
                                    Logger.warn("Browser", "Loading initial URL: " + tabs[currentTabIndex].url)
                                    url = tabs[currentTabIndex].url
                                }
                            })
                        }
                    }
                }
                
                Loader {
                    id: webViewLoader
                    anchors.fill: parent
                    sourceComponent: webEngineComponent
                    asynchronous: false
                    
                    onLoaded: {
                        Logger.warn("Browser", "Loader.onLoaded fired")
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: Constants.gestureEdgeWidth
                    propagateComposedEvents: true
                    z: -100
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
                    
                    onPressed: (mouse) => {
                        startX = mouse.x + rightEdgeGesture.x
                        currentX = startX
                        isDragging = true
                    }
                    
                    onPositionChanged: (mouse) => {
                        currentX = mouse.x + rightEdgeGesture.x
                        var deltaX = startX - currentX
                        drawerProgress = Math.max(0, Math.min(1, deltaX / (contentArea.width * 0.85)))
                    }
                    
                    onReleased: {
                        isDragging = false
                        if (drawerProgress > 0.3) {
                            openDrawer()
                        } else {
                            closeDrawer()
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
                        var currentTab = getCurrentTab()
                        if (currentTab && currentTab.isLoading && currentTab.loadProgress) {
                            return parent.width * (currentTab.loadProgress / 100)
                        }
                        return 0
                    }
                    color: MColors.accent
                    visible: {
                        var currentTab = getCurrentTab()
                        return currentTab && currentTab.isLoading === true
                    }
                    
                    Behavior on width {
                        NumberAnimation { duration: 100 }
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
                                var currentTab = getCurrentTab()
                                return (currentTab && currentTab.canGoBack) ? MColors.text : MColors.textTertiary
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            enabled: {
                                if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
                                    var tab = tabs[currentTabIndex]
                                    return tab && tab.canGoBack === true
                                }
                                return false
                            }
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                HapticService.light()
                                if (webView && webView.canGoBack) {
                                    webView.goBack()
                                }
                            }
                        }
                    }
                    
                    // Forward button removed to save space
                    
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
                                var currentTab = getCurrentTab()
                                return currentTab ? currentTab.url : ""
                            }
                            
                            Connections {
                                target: browserApp
                                function onAppLaunched() {
                                    Qt.callLater(function() {
                                        urlInput.focus = true
                                        urlInput.selectAll()
                                    })
                                }
                                function onAppResumed() {
                                    Qt.callLater(function() {
                                        urlInput.focus = true
                                        urlInput.selectAll()
                                    })
                                }
                            }
                            
                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    selectAll()
                                }
                            }
                            
                            onAccepted: {
                                HapticService.light()
                                navigateTo(text)
                                urlInput.focus = false
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
                                        HapticService.light()
                                        urlInput.text = ""
                                        urlInput.focus = true
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
                                        var currentTab = getCurrentTab()
                                        return (currentTab && isBookmarked(currentTab.url)) ? MColors.accent : MColors.textSecondary
                                    }
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        HapticService.light()
                                        var currentTab = getCurrentTab()
                                        if (currentTab) {
                                            if (isBookmarked(currentTab.url)) {
                                                removeBookmark(currentTab.url)
                                            } else {
                                                addBookmark(currentTab.url, currentTab.title)
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
                                        var currentTab = getCurrentTab()
                                        return (currentTab && currentTab.isLoading) ? "x" : "refresh-cw"
                                    }
                                    size: Constants.iconSizeSmall * 0.8
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        HapticService.light()
                                        if (webView) {
                                            var currentTab = getCurrentTab()
                                            if (currentTab && currentTab.isLoading) {
                                                webView.stop()
                                            } else {
                                                webView.reload()
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
                                text: "(" + tabs.length + ")"
                                font.pixelSize: MTypography.sizeSmall * 0.85
                                font.weight: Font.Normal
                                color: MColors.textTertiary
                                visible: tabs.length > 0
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                HapticService.light()
                                if (isDrawerOpen) {
                                    closeDrawer()
                                } else {
                                    openDrawer()
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
                    closeDrawer()
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
                    browserApp.drawerRef = drawer
                    
                    if (drawer.tabsPage) {
                        drawer.tabsPage.tabs = Qt.binding(function() { return browserApp.tabs })
                        drawer.tabsPage.currentTabId = Qt.binding(function() {
                            var currentTab = browserApp.getCurrentTab()
                            return currentTab ? currentTab.id : -1
                        })
                    }
                    
                    if (drawer.bookmarksPage) {
                        drawer.bookmarksPage.bookmarks = Qt.binding(function() { return browserApp.bookmarks })
                    }
                    
                    if (drawer.historyPage) {
                        drawer.historyPage.history = Qt.binding(function() { return browserApp.history })
                    }
                    
                    if (drawer.settingsPage) {
                        var savedSearchEngine = SettingsManagerCpp.get("browser/searchEngine", "Google")
                        var savedSearchEngineUrl = SettingsManagerCpp.get("browser/searchEngineUrl", "https://www.google.com/search?q=")
                        var savedHomepage = SettingsManagerCpp.get("browser/homepage", "https://www.google.com")
                        
                        drawer.settingsPage.searchEngine = savedSearchEngine
                        drawer.settingsPage.searchEngineUrl = savedSearchEngineUrl
                        drawer.settingsPage.homepage = savedHomepage
                        drawer.settingsPage.isPrivateMode = Qt.binding(function() { return browserApp.isPrivateMode })
                        
                        drawer.settingsPage.isPrivateModeChanged.connect(function() {
                            browserApp.isPrivateMode = drawer.settingsPage.isPrivateMode
                        })
                        
                        drawer.settingsPage.searchEngineChanged.connect(function() {
                            SettingsManagerCpp.set("browser/searchEngine", drawer.settingsPage.searchEngine)
                        })
                        
                        drawer.settingsPage.searchEngineUrlChanged.connect(function() {
                            SettingsManagerCpp.set("browser/searchEngineUrl", drawer.settingsPage.searchEngineUrl)
                        })
                        
                        drawer.settingsPage.homepageChanged.connect(function() {
                            SettingsManagerCpp.set("browser/homepage", drawer.settingsPage.homepage)
                        })
                    }
                }
                
                onClosed: {
                    closeDrawer()
                }
                
                onTabSelected: (tabId) => {
                    switchToTab(tabId)
                    closeDrawer()
                }
                
                onNewTabRequested: {
                    var tabId = createNewTab()
                    if (tabId >= 0) {
                        closeDrawer()
                    }
                }
                
                onBookmarkSelected: (url) => {
                    navigateTo(url)
                }
                
                onHistorySelected: (url) => {
                    navigateTo(url)
                }
                
                Connections {
                    target: drawer.tabsPage
                    function onCloseTab(tabId) {
                        browserApp.closeTab(tabId)
                    }
                }
                
                Connections {
                    target: drawer.bookmarksPage
                    function onDeleteBookmark(url) {
                        browserApp.removeBookmark(url)
                    }
                }
                
                Connections {
                    target: drawer.historyPage
                    function onClearHistory() {
                        browserApp.clearHistory()
                    }
                }
                
                Connections {
                    target: drawer.settingsPage
                    function onClearHistoryRequested() {
                        if (!browserApp.isPrivateMode) {
                            browserApp.clearHistory()
                        }
                    }
                    
                    function onClearCookiesRequested() {
                        if (webView && webView.profile) {
                            webView.profile.clearAllVisitedLinks()
                            Logger.info("BrowserApp", "Cleared cookies and site data")
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
                Logger.info("BrowserApp", "Deep link requested with params: " + JSON.stringify(params))
                
                // Handle URL parameter
                if (params && params.url) {
                    Logger.info("BrowserApp", "Opening URL from deep link: " + params.url)
                    navigateTo(params.url)
                }
            }
        }
    }
    
    onAppPaused: {
        saveTabs()
        saveBookmarks()
        saveHistory()
    }
    
    onAppClosed: {
        if (webView) {
            webView.stop()
            webView.url = "about:blank"
            webView = null
        }
        
        saveTabs()
        saveBookmarks()
        saveHistory()
    }
    
    Component.onDestruction: {
        if (backConnection) {
            browserApp.backPressed.disconnect(backConnection)
            backConnection = null
        }
        
        if (forwardConnection) {
            browserApp.forwardPressed.disconnect(forwardConnection)
            forwardConnection = null
        }
        
        if (webView) {
            webView.stop()
            webView.url = "about:blank"
            webView = null
        }
    }
}
