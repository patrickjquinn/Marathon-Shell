pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: searchService

    property var searchIndex: []
    property var recentSearches: []
    property bool isIndexing: false
    property int maxRecentSearches: 10

    signal searchCompleted(var results)
    signal indexingComplete()

    function buildSearchIndex() {
        Logger.info("UnifiedSearch", "Building search index...")
        isIndexing = true
        searchIndex = []

        var allApps = AppStore.apps
        for (var i = 0; i < allApps.length; i++) {
            var app = allApps[i]
            searchIndex.push({
                type: "app",
                id: app.id,
                title: app.name,
                subtitle: app.type === "native" ? "Native App" : "Marathon App",
                icon: app.icon,
                keywords: [app.name.toLowerCase()],
                data: app,
                score: 0
            })
        }

        var settingsCategories = [
            { id: "wifi", title: "Wi-Fi", subtitle: "Network Settings", keywords: ["wifi", "wireless", "network", "internet", "connection"] },
            { id: "bluetooth", title: "Bluetooth", subtitle: "Device Connections", keywords: ["bluetooth", "bt", "wireless", "device", "pair"] },
            { id: "display", title: "Display", subtitle: "Screen & Brightness", keywords: ["display", "screen", "brightness", "auto-brightness", "wallpaper"] },
            { id: "sound", title: "Sound", subtitle: "Volume & Ringtones", keywords: ["sound", "volume", "ringtone", "notification", "audio"] },
            { id: "notifications", title: "Notifications", subtitle: "App Alerts", keywords: ["notifications", "alerts", "badges", "sounds"] },
            { id: "security", title: "Security", subtitle: "Lock Screen & Privacy", keywords: ["security", "privacy", "lock", "pin", "password", "biometric"] },
            { id: "battery", title: "Battery", subtitle: "Power Management", keywords: ["battery", "power", "charging", "saver"] },
            { id: "storage", title: "Storage", subtitle: "Space & Files", keywords: ["storage", "space", "memory", "files", "disk"] },
            { id: "accounts", title: "Accounts", subtitle: "Sign In & Sync", keywords: ["accounts", "sync", "login", "sign in", "email"] },
            { id: "about", title: "About", subtitle: "System Information", keywords: ["about", "version", "info", "system", "device"] }
        ]

        for (var j = 0; j < settingsCategories.length; j++) {
            var setting = settingsCategories[j]
            searchIndex.push({
                type: "setting",
                id: setting.id,
                title: setting.title,
                subtitle: setting.subtitle,
                icon: "qrc:/images/settings.svg",
                keywords: setting.keywords,
                data: setting,
                score: 0
            })
        }

        isIndexing = false
        indexingComplete()
        Logger.info("UnifiedSearch", "Index built: " + searchIndex.length + " items")
    }

    function search(query) {
        if (!query || query.trim().length === 0) {
            return []
        }

        var normalizedQuery = query.toLowerCase().trim()
        var results = []

        for (var i = 0; i < searchIndex.length; i++) {
            var item = searchIndex[i]
            var score = calculateScore(item, normalizedQuery)

            if (score > 0) {
                var result = Object.assign({}, item)
                result.score = score
                results.push(result)
            }
        }

        results.sort(function(a, b) {
            if (b.score !== a.score) {
                return b.score - a.score
            }
            return a.title.localeCompare(b.title)
        })

        searchCompleted(results)
        return results
    }

    function calculateScore(item, query) {
        var score = 0
        var title = item.title.toLowerCase()

        if (title === query) {
            score += 1000
        } else if (title.startsWith(query)) {
            score += 500
        } else if (title.indexOf(query) !== -1) {
            score += 250
        }

        for (var i = 0; i < item.keywords.length; i++) {
            var keyword = item.keywords[i]
            if (keyword === query) {
                score += 750
            } else if (keyword.startsWith(query)) {
                score += 400
            } else if (keyword.indexOf(query) !== -1) {
                score += 200
            }
        }

        if (item.subtitle) {
            var subtitle = item.subtitle.toLowerCase()
            if (subtitle.indexOf(query) !== -1) {
                score += 100
            }
        }

        score += fuzzyMatch(title, query) * 50

        if (item.type === "app") {
            score += 50
        }

        return score
    }

    function fuzzyMatch(text, pattern) {
        var patternIdx = 0
        var score = 0
        var consecutiveMatches = 0

        for (var i = 0; i < text.length && patternIdx < pattern.length; i++) {
            if (text[i] === pattern[patternIdx]) {
                score += 1 + consecutiveMatches
                consecutiveMatches++
                patternIdx++
            } else {
                consecutiveMatches = 0
            }
        }

        if (patternIdx === pattern.length) {
            return score / pattern.length
        }

        return 0
    }

    function addToRecentSearches(query) {
        if (!query || query.trim().length === 0) {
            return
        }

        var normalized = query.trim()

        var existingIndex = recentSearches.indexOf(normalized)
        if (existingIndex !== -1) {
            recentSearches.splice(existingIndex, 1)
        }

        recentSearches.unshift(normalized)

        if (recentSearches.length > maxRecentSearches) {
            recentSearches = recentSearches.slice(0, maxRecentSearches)
        }
    }

    function clearRecentSearches() {
        recentSearches = []
    }

    function executeSearchResult(result) {
        Logger.info("UnifiedSearch", "Executing result: " + result.type + " - " + result.title)

        if (result.type === "app") {
            var app = result.data
            if (app.id === "settings") {
                UIStore.openSettings()
                if (typeof AppLifecycleManager !== 'undefined') {
                    AppLifecycleManager.bringToForeground("settings")
                }
            } else {
                UIStore.openApp(app.id, app.name, app.icon)
            }
        } else if (result.type === "setting") {
            UIStore.openSettings()
            Router.navigateToSetting(result.id)
        }
    }

    Component.onCompleted: {
        Logger.info("UnifiedSearch", "Unified Search Service initialized")
        buildSearchIndex()

        AppStore.onAppsChanged.connect(function() {
            Logger.info("UnifiedSearch", "App list changed, rebuilding index")
            buildSearchIndex()
        })
    }
}

