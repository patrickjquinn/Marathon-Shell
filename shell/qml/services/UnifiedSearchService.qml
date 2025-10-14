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

        // Get apps from C++ AppModel using getAppAtIndex
        var appCount = AppModel.count
        Logger.info("UnifiedSearch", "Indexing " + appCount + " apps from AppModel")
        
        var actualAppsAdded = 0
        for (var i = 0; i < appCount; i++) {
            var app = AppModel.getAppAtIndex(i)
            if (!app) {
                Logger.warning("UnifiedSearch", "Failed to get app at index " + i)
                continue
            }
            
            var appId = app.id
            var appName = app.name
            var appIcon = app.icon
            var appType = app.type
            
            if (appName && appId) {
                var keywords = [
                    appName.toLowerCase(),
                    appId.toLowerCase()
                ]
                
                // Add word fragments for better matching
                var nameParts = appName.toLowerCase().split(/\s+/)
                for (var j = 0; j < nameParts.length; j++) {
                    if (nameParts[j].length > 0) {
                        keywords.push(nameParts[j])
                    }
                }
                
                searchIndex.push({
                    type: "app",
                    id: appId,
                    title: appName,
                    subtitle: appType === "native" ? "Native App" : "Marathon App",
                    icon: appIcon,
                    keywords: keywords,
                    searchText: appName.toLowerCase() + " " + appId.toLowerCase(),
                    data: { id: appId, name: appName, icon: appIcon, type: appType },
                    score: 0
                })
                
                actualAppsAdded++
            }
        }

        Logger.info("UnifiedSearch", "Added " + actualAppsAdded + " apps to search index")

        var settingsCategories = [
            { id: "wifi", title: "Wi-Fi", subtitle: "Network Settings", keywords: ["wifi", "wireless", "network", "internet", "connection", "wi-fi"] },
            { id: "bluetooth", title: "Bluetooth", subtitle: "Device Connections", keywords: ["bluetooth", "bt", "wireless", "device", "pair", "pairing"] },
            { id: "display", title: "Display", subtitle: "Screen & Brightness", keywords: ["display", "screen", "brightness", "auto-brightness", "wallpaper", "theme"] },
            { id: "sound", title: "Sound", subtitle: "Volume & Ringtones", keywords: ["sound", "volume", "ringtone", "notification", "audio", "music"] },
            { id: "notifications", title: "Notifications", subtitle: "App Alerts", keywords: ["notifications", "alerts", "badges", "sounds", "banner"] },
            { id: "security", title: "Security", subtitle: "Lock Screen & Privacy", keywords: ["security", "privacy", "lock", "pin", "password", "biometric", "fingerprint"] },
            { id: "battery", title: "Battery", subtitle: "Power Management", keywords: ["battery", "power", "charging", "saver", "energy"] },
            { id: "storage", title: "Storage", subtitle: "Space & Files", keywords: ["storage", "space", "memory", "files", "disk", "capacity"] },
            { id: "accounts", title: "Accounts", subtitle: "Sign In & Sync", keywords: ["accounts", "sync", "login", "sign in", "email", "user"] },
            { id: "about", title: "About", subtitle: "System Information", keywords: ["about", "version", "info", "system", "device", "build"] }
        ]

        for (var k = 0; k < settingsCategories.length; k++) {
            var setting = settingsCategories[k]
            searchIndex.push({
                type: "setting",
                id: setting.id,
                title: setting.title,
                subtitle: setting.subtitle,
                icon: "qrc:/images/settings.svg",
                keywords: setting.keywords,
                searchText: setting.title.toLowerCase() + " " + setting.keywords.join(" "),
                data: setting,
                score: 0
            })
        }

        isIndexing = false
        indexingComplete()
        Logger.info("UnifiedSearch", "Index built: " + searchIndex.length + " items (" + actualAppsAdded + " apps + " + settingsCategories.length + " settings)")
    }

    function search(query) {
        if (!query || query.trim().length === 0) {
            return []
        }

        var normalizedQuery = query.toLowerCase().trim()
        var results = []

        // Fast path: exact matches first
        for (var i = 0; i < searchIndex.length; i++) {
            var item = searchIndex[i]
            var score = 0
            
            // 1. Exact title match (highest priority)
            if (item.title.toLowerCase() === normalizedQuery) {
                score = 10000
            }
            // 2. Title starts with query (very high priority)
            else if (item.title.toLowerCase().startsWith(normalizedQuery)) {
                score = 5000
            }
            // 3. Exact keyword match
            else if (item.keywords.indexOf(normalizedQuery) !== -1) {
                score = 3000
            }
            // 4. Any keyword starts with query
            else {
                for (var j = 0; j < item.keywords.length; j++) {
                    if (item.keywords[j].startsWith(normalizedQuery)) {
                        score = Math.max(score, 2000)
                        break
                    }
                }
            }
            
            // 5. Title contains query
            if (score === 0 && item.title.toLowerCase().indexOf(normalizedQuery) !== -1) {
                score = 1000
            }
            
            // 6. Any keyword contains query
            if (score === 0) {
                for (var m = 0; m < item.keywords.length; m++) {
                    if (item.keywords[m].indexOf(normalizedQuery) !== -1) {
                        score = Math.max(score, 500)
                    }
                }
            }
            
            // 7. Fuzzy match on searchText
            if (score === 0) {
                var fuzzyScore = fuzzyMatch(item.searchText, normalizedQuery)
                if (fuzzyScore > 0) {
                    score = fuzzyScore * 100
                }
            }
            
            // Boost apps over settings
            if (score > 0 && item.type === "app") {
                score += 100
            }

            if (score > 0) {
                var result = Object.assign({}, item)
                result.score = score
                results.push(result)
            }
        }

        // Sort by score (highest first), then alphabetically
        results.sort(function(a, b) {
            if (b.score !== a.score) {
                return b.score - a.score
            }
            return a.title.localeCompare(b.title)
        })

        searchCompleted(results)
        Logger.info("UnifiedSearch", "Search for '" + query + "' returned " + results.length + " results")
        return results
    }

    function fuzzyMatch(text, pattern) {
        var patternIdx = 0
        var score = 0
        var consecutiveMatches = 0
        var textIdx = 0

        while (textIdx < text.length && patternIdx < pattern.length) {
            if (text[textIdx] === pattern[patternIdx]) {
                score += 1 + consecutiveMatches * 2  // Bonus for consecutive chars
                consecutiveMatches++
                patternIdx++
            } else {
                consecutiveMatches = 0
            }
            textIdx++
        }

        // Full match required
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
            if (typeof Router !== 'undefined') {
                Router.navigateToSetting(result.id)
            }
        }
    }

    Component.onCompleted: {
        Logger.info("UnifiedSearch", "Unified Search Service initialized")
        buildSearchIndex()

        // Rebuild index when apps change
        AppModel.countChanged.connect(function() {
            Logger.info("UnifiedSearch", "App count changed, rebuilding index")
            buildSearchIndex()
        })
    }
}
