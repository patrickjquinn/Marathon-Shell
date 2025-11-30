pragma Singleton
import QtQuick
import MarathonOS.Shell

/**
 * @singleton
 * @brief Handles Marathon URI scheme navigation and deep linking
 *
 * NavigationRouter provides a centralized system for navigating between
 * apps and pages using Marathon URIs (marathon://app/page?params).
 * Supports deep linking, navigation history, and app launching.
 *
 * URI Format: `marathon://appId/page?param1=value1&param2=value2`
 *
 * @example
 * // Navigate to settings WiFi page
 * NavigationRouter.navigate("marathon://settings/wifi")
 *
 * @example
 * // Open browser with URL
 * NavigationRouter.navigate("marathon://browser/view?url=https://example.com")
 *
 * @example
 * // Quick launch shortcut
 * NavigationRouter.quickLaunch("camera")
 */
QtObject {
    id: router

    /**
     * @brief Currently active app ID
     * @type {string}
     */
    property string currentApp: ""

    /**
     * @brief Currently active page within the app
     * @type {string}
     */
    property string currentPage: ""

    /**
     * @brief Current navigation parameters
     * @type {Object}
     */
    property var currentParams: ({})

    /**
     * @brief Navigation history stack
     * @type {Array<Object>}
     */
    property var history: []

    /**
     * @brief Emitted when navigation succeeds
     * @param {string} uri - The URI that was navigated to
     */
    signal navigated(string uri)

    /**
     * @brief Emitted when navigation fails
     * @param {string} uri - The URI that failed
     * @param {string} error - Error message
     */
    signal navigationFailed(string uri, string error)

    /**
     * @brief Navigates to a Marathon URI
     *
     * @param {string} uri - Full Marathon URI (marathon://app/page?params)
     * @returns {bool} Success status
     *
     * @example
     * NavigationRouter.navigate("marathon://settings/display")
     */
    function navigate(uri) {
        Logger.info("NavigationRouter", "Navigate to: " + uri);

        var parsed = parseURI(uri);
        if (!parsed.valid) {
            var error = "Invalid URI format: " + uri;
            Logger.error("NavigationRouter", error);
            navigationFailed(uri, error);
            return false;
        }

        // Add to history
        history.push({
            uri: uri,
            app: parsed.app,
            page: parsed.page,
            params: parsed.params,
            timestamp: Date.now()
        });

        // Update current state
        currentApp = parsed.app;
        currentPage = parsed.page;
        currentParams = parsed.params;

        // Route to appropriate handler
        if (parsed.app === "hub") {
            return handleHubRoute(parsed);
        } else if (parsed.app === "browser") {
            return handleBrowserRoute(parsed);
        } else {
            // Generic app launch (includes Settings now)
            return handleAppRoute(parsed);
        }
    }

    /**
     * Go back in navigation history
     */
    function goBack() {
        if (history.length > 1) {
            history.pop(); // Remove current
            var previous = history[history.length - 1];
            navigate(previous.uri);
            return true;
        }
        return false;
    }

    /**
     * Clear navigation history
     */
    function clearHistory() {
        history = [];
        currentApp = "";
        currentPage = "";
        currentParams = {};
        Logger.info("NavigationRouter", "Navigation history cleared");
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
        };

        // Check for marathon:// scheme
        if (!uri.startsWith("marathon://")) {
            return result;
        }

        // Remove scheme
        var path = uri.substring("marathon://".length);

        // Split query params
        var pathAndQuery = path.split("?");
        var pathParts = pathAndQuery[0].split("/");

        // Parse path
        result.app = pathParts[0] || "";
        result.page = pathParts[1] || "";
        result.subpage = pathParts[2] || "";

        // Parse query params
        if (pathAndQuery.length > 1) {
            var queryString = pathAndQuery[1];
            var queryParts = queryString.split("&");
            for (var i = 0; i < queryParts.length; i++) {
                var pair = queryParts[i].split("=");
                if (pair.length === 2) {
                    result.params[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1]);
                }
            }
        }

        result.valid = result.app !== "";
        return result;
    }

    /**
     * Handle Hub routing
     */
    function handleHubRoute(parsed) {
        Logger.info("NavigationRouter", "Routing to Hub: " + parsed.page);

        // Open Hub and select tab
        if (parsed.page === "messages") {
            // Navigate to messages tab
            hubTabRequested(0);
        } else if (parsed.page === "notifications") {
            hubTabRequested(1);
        } else if (parsed.page === "calendar") {
            hubTabRequested(2);
        }

        navigated("marathon://hub/" + parsed.page);
        return true;
    }

    /**
     * Handle Browser routing
     */
    function handleBrowserRoute(parsed) {
        Logger.info("NavigationRouter", "Routing to Browser");

        var url = parsed.params.url || "";

        // Launch browser with URL parameter
        deepLinkRequested("browser", "", {
            url: url
        });

        navigated("marathon://browser");
        return true;
    }

    /**
     * Handle generic app routing
     */
    function handleAppRoute(parsed) {
        Logger.info("NavigationRouter", "Routing to app: " + parsed.app);

        // Request app launch via deep link signal
        deepLinkRequested(parsed.app, "", {});

        navigated("marathon://" + parsed.app);
        return true;
    }

    // Signals for specific navigation events
    signal settingsNavigationRequested(string page, string subpage, var params)
    signal hubTabRequested(int tabIndex)
    signal deepLinkRequested(string appId, string route, var params)

    function navigateToDeepLink(appId, route, params) {
        Logger.info("NavigationRouter", "Deep link requested: " + appId + " → " + route);

        // Get app info
        var appInfo = typeof MarathonAppRegistry !== 'undefined' ? MarathonAppRegistry.getApp(appId) : null;

        if (!appInfo) {
            Logger.error("NavigationRouter", "App not found for deep link: " + appId);
            return false;
        }

        // Check if THIS specific app is already open
        var isAppOpen = (UIStore.appWindowOpen && UIStore.currentAppId === appId);

        if (!isAppOpen) {
            // Launch the app first using UIStore
            UIStore.openApp(appId, appInfo.name, appInfo.icon);
        }

        // Emit deep link signal for app to handle (after a small delay if we just opened it)
        if (isAppOpen) {
            deepLinkRequested(appId, route, params || {});
        } else {
            Qt.callLater(function () {
                deepLinkRequested(appId, route, params || {});
            });
        }

        return true;
    }

    Component.onCompleted: {
        Logger.info("NavigationRouter", "Initialized");
    }
}
