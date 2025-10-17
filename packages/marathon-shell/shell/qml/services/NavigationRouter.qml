pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: router
    
    // Current navigation state
    property string currentApp: ""
    property string currentPage: ""
    property var currentParams: ({})
    
    // Navigation history
    property var history: []
    
    signal navigated(string uri)
    signal navigationFailed(string uri, string error)
    
    /**
     * Navigate to a Marathon URI
     * @param uri {string} - Full Marathon URI (marathon://app/page?params)
     * @returns {bool} - Success status
     */
    function navigate(uri) {
        Logger.info("NavigationRouter", "Navigate to: " + uri)
        
        var parsed = parseURI(uri)
        if (!parsed.valid) {
            var error = "Invalid URI format: " + uri
            Logger.error("NavigationRouter", error)
            navigationFailed(uri, error)
            return false
        }
        
        // Add to history
        history.push({
            uri: uri,
            app: parsed.app,
            page: parsed.page,
            params: parsed.params,
            timestamp: Date.now()
        })
        
        // Update current state
        currentApp = parsed.app
        currentPage = parsed.page
        currentParams = parsed.params
        
        // Route to appropriate handler
        if (parsed.app === "hub") {
            return handleHubRoute(parsed)
        } else if (parsed.app === "browser") {
            return handleBrowserRoute(parsed)
        } else {
            // Generic app launch (includes Settings now)
            return handleAppRoute(parsed)
        }
    }
    
    /**
     * Go back in navigation history
     */
    function goBack() {
        if (history.length > 1) {
            history.pop() // Remove current
            var previous = history[history.length - 1]
            navigate(previous.uri)
            return true
        }
        return false
    }
    
    /**
     * Clear navigation history
     */
    function clearHistory() {
        history = []
        currentApp = ""
        currentPage = ""
        currentParams = {}
        Logger.info("NavigationRouter", "Navigation history cleared")
    }
    
    /**
     * Parse Marathon URI into components
     * @param uri {string} - Marathon URI
     * @returns {object} - Parsed components
     */
    function parseURI(uri) {
        var result = {
            valid: false,
            app: "",
            page: "",
            subpage: "",
            params: {}
        }
        
        // Check for marathon:// scheme
        if (!uri.startsWith("marathon://")) {
            return result
        }
        
        // Remove scheme
        var path = uri.substring("marathon://".length)
        
        // Split query params
        var pathAndQuery = path.split("?")
        var pathParts = pathAndQuery[0].split("/")
        
        // Parse path
        result.app = pathParts[0] || ""
        result.page = pathParts[1] || ""
        result.subpage = pathParts[2] || ""
        
        // Parse query params
        if (pathAndQuery.length > 1) {
            var queryString = pathAndQuery[1]
            var queryParts = queryString.split("&")
            for (var i = 0; i < queryParts.length; i++) {
                var pair = queryParts[i].split("=")
                if (pair.length === 2) {
                    result.params[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1])
                }
            }
        }
        
        result.valid = result.app !== ""
        return result
    }
    
    /**
     * Handle Hub routing
     */
    function handleHubRoute(parsed) {
        Logger.info("NavigationRouter", "Routing to Hub: " + parsed.page)
        
        // Open Hub and select tab
        if (parsed.page === "messages") {
            // Navigate to messages tab
            hubTabRequested(0)
        } else if (parsed.page === "notifications") {
            hubTabRequested(1)
        } else if (parsed.page === "calendar") {
            hubTabRequested(2)
        }
        
        navigated("marathon://hub/" + parsed.page)
        return true
    }
    
    /**
     * Handle Browser routing
     */
    function handleBrowserRoute(parsed) {
        Logger.info("NavigationRouter", "Routing to Browser")
        
        var url = parsed.params.url || ""
        AppStore.launchApp("browser")
        
        // TODO: Pass URL to browser when app integration is complete
        
        navigated("marathon://browser")
        return true
    }
    
    /**
     * Handle generic app routing
     */
    function handleAppRoute(parsed) {
        Logger.info("NavigationRouter", "Routing to app: " + parsed.app)
        
        // Request app launch via deep link signal
        deepLinkRequested(parsed.app, "", {})
        
        navigated("marathon://" + parsed.app)
        return true
    }
    
    // Signals for specific navigation events
    signal settingsNavigationRequested(string page, string subpage, var params)
    signal hubTabRequested(int tabIndex)
    signal deepLinkRequested(string appId, string route, var params)
    
    function navigateToDeepLink(appId, route, params) {
        Logger.info("NavigationRouter", "Deep link requested: " + appId + " → " + route)
        
        // Launch app if not already open
        var appInfo = typeof MarathonAppRegistry !== 'undefined' ? 
                      MarathonAppRegistry.getApp(appId) : null
        
        if (appInfo) {
            // Launch the app first
            AppStore.launchApp(appId)
            
            // Emit deep link signal for app to handle
            deepLinkRequested(appId, route, params || {})
            
            // Legacy: Settings still uses old signal
            if (appId === "settings") {
                settingsNavigationRequested(route, "", params || {})
            }
            
            return true
        }
        
        Logger.error("NavigationRouter", "App not found for deep link: " + appId)
        return false
    }
    
    Component.onCompleted: {
        Logger.info("NavigationRouter", "Initialized")
    }
}

