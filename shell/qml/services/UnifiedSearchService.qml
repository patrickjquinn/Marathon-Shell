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
        console.error("===== buildSearchIndex() CALLED =====")
        Logger.error("UnifiedSearch", "Building search index...")
        isIndexing = true
        searchIndex = []

        // Get apps from C++ AppModel using getAppAtIndex
        var appCount = AppModel.count
        console.error("AppModel.count =", appCount)
        Logger.error("UnifiedSearch", "Indexing " + appCount + " apps from AppModel")
        
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
        console.error("Added", actualAppsAdded, "apps to index")

        // Index deep links from all apps in MarathonAppRegistry
        var deepLinkCount = 0
        if (typeof MarathonAppRegistry !== 'undefined') {
            var registryCount = MarathonAppRegistry.count
            console.error("===== INDEXING DEEP LINKS, MarathonAppRegistry.count =", registryCount, "=====")
            Logger.error("UnifiedSearch", "Indexing deep links from " + registryCount + " apps in registry")
            
            for (var j = 0; j < registryCount; j++) {
                // Use getApp() instead of data() - much simpler!
                var allAppIds = MarathonAppRegistry.getAllAppIds()
                if (j >= allAppIds.length) break
                
                var appId = allAppIds[j]
                var appData = MarathonAppRegistry.getApp(appId)
                
                if (!appData || !appData.id) {
                    console.error("Failed to get app data for index", j)
                    continue
                }
                
                var registryApp = appData.id
                var appName = appData.name
                var appIcon = appData.icon
                var deepLinksJson = appData.deepLinks
                
                console.error("App", j, ":", registryApp, "- deepLinksJson:", deepLinksJson)
                Logger.error("UnifiedSearch", "App " + j + ": " + registryApp + " (" + appName + ") - deepLinks JSON length: " + (deepLinksJson ? deepLinksJson.length : 0))
                
                if (deepLinksJson && deepLinksJson.length > 0) {
                    console.error("  Has deep links JSON, length:", deepLinksJson.length)
                    Logger.error("UnifiedSearch", "Deep links JSON for " + registryApp + ": " + deepLinksJson)
                    try {
                        var deepLinks = JSON.parse(deepLinksJson)
                        var linkCount = 0
                        
                        for (var route in deepLinks) {
                            var link = deepLinks[route]
                            var linkKeywords = link.keywords || []
                            
                            // Add app name as extra context
                            linkKeywords.push(appName.toLowerCase())
                            linkKeywords.push(route.toLowerCase())
                            
                            Logger.info("UnifiedSearch", "  Adding deep link: " + link.title + " (route: " + route + ")")
                            
                            searchIndex.push({
                                type: "deeplink",
                                id: route,
                                appId: registryApp,
                                title: link.title || route,
                                subtitle: link.description || appName,
                                icon: appIcon || "qrc:/images/app-icon-placeholder.svg",
                                keywords: linkKeywords,
                                searchText: (link.title || route).toLowerCase() + " " + linkKeywords.join(" "),
                                data: {
                                    appId: registryApp,
                                    route: route,
                                    appName: appName
                                },
                                score: 0
                            })
                            
                            deepLinkCount++
                            linkCount++
                        }
                        
                        Logger.info("UnifiedSearch", "  Added " + linkCount + " deep links for " + registryApp)
                    } catch (e) {
                        Logger.error("UnifiedSearch", "Failed to parse deep links for " + registryApp + ": " + e)
                    }
                } else {
                    Logger.info("UnifiedSearch", "  No deep links for " + registryApp)
                }
            }
            
            Logger.info("UnifiedSearch", "Indexed " + deepLinkCount + " deep links")
        } else {
            Logger.warning("UnifiedSearch", "MarathonAppRegistry is undefined!")
        }

        isIndexing = false
        indexingComplete()
        Logger.info("UnifiedSearch", "Index built: " + searchIndex.length + " items (" + actualAppsAdded + " apps + " + deepLinkCount + " deep links)")
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
        console.error("===== executeSearchResult() CALLED, type:", result.type, "title:", result.title, "=====")
        Logger.error("UnifiedSearch", "Executing result: " + result.type + " - " + result.title)

        if (result.type === "app") {
            // Launch app through UIStore
            var app = result.data
            console.error("Launching app:", app.id)
            UIStore.openApp(app.id, app.name, app.icon)
        } else if (result.type === "setting") {
            // Legacy setting support (deprecated - use deeplink instead)
            console.error("Opening settings (legacy)")
            UIStore.openSettings()
            if (typeof Router !== 'undefined') {
                Router.navigateToSetting(result.id)
            }
        } else if (result.type === "deeplink") {
            // NEW: Deep link navigation (core Marathon app pattern)
            var linkData = result.data
            console.error("Navigating to deep link:", linkData.appId, "→", linkData.route)
            Logger.error("UnifiedSearch", "Navigating to deep link: " + linkData.appId + " → " + linkData.route)
            
            if (typeof NavigationRouter !== 'undefined') {
                NavigationRouter.navigateToDeepLink(linkData.appId, linkData.route, {})
            } else {
                Logger.error("UnifiedSearch", "NavigationRouter not available")
            }
        }
    }

    Component.onCompleted: {
        console.error("===== UNIFIED SEARCH SERVICE STARTING =====")
        Logger.error("UnifiedSearch", "Unified Search Service initialized")
        
        // Wait for app scanner to complete before building index
        if (typeof MarathonAppScanner !== 'undefined') {
            console.error("MarathonAppScanner EXISTS, connecting to scanComplete")
            MarathonAppScanner.scanComplete.connect(function(count) {
                console.error("===== SCAN COMPLETE, COUNT:", count, "=====")
                Logger.error("UnifiedSearch", "App scan complete with " + count + " apps, building search index...")
                buildSearchIndex()
            })
            
            // If scan already happened, build immediately
            if (typeof MarathonAppRegistry !== 'undefined' && MarathonAppRegistry.count > 0) {
                console.error("MarathonAppRegistry ALREADY HAS", MarathonAppRegistry.count, "apps, building NOW")
                Logger.error("UnifiedSearch", "Apps already loaded, building index immediately")
                buildSearchIndex()
            } else {
                console.error("MarathonAppRegistry count is 0 or undefined, WAITING for scan")
            }
        } else {
            console.error("MarathonAppScanner UNDEFINED, building immediately as fallback")
            // Fallback: build index immediately
            Logger.error("UnifiedSearch", "MarathonAppScanner not available, building index immediately")
            buildSearchIndex()
        }

        // Rebuild index when apps change
        if (typeof AppModel !== 'undefined') {
            AppModel.countChanged.connect(function() {
                Logger.info("UnifiedSearch", "App count changed, rebuilding index")
                buildSearchIndex()
            })
        }
    }
}
