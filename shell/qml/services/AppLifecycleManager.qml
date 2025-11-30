pragma Singleton
import QtQuick
import MarathonOS.Shell

/**
 * @singleton
 * @brief Centralized app lifecycle management
 *
 * AppLifecycleManager tracks running apps, manages their state transitions,
 * and coordinates system events (back gesture, minimize, close). Works with
 * MApp components to provide Android/iOS-like app lifecycle.
 *
 * Responsibilities:
 * - Track running apps and their state (active, paused, minimized)
 * - Handle app lifecycle events (launch, pause, resume, close)
 * - Manage app stack (foreground, background)
 * - Route system events to apps (back gesture, home button, etc.)
 * - Coordinate with UIStore and TaskModel
 *
 * @example
 * // Bring app to foreground
 * AppLifecycleManager.bringToForeground("messages")
 *
 * @example
 * // Check if app is running
 * if (AppLifecycleManager.isAppRunning("settings")) {
 *     AppLifecycleManager.bringToForeground("settings")
 * } else {
 *     // Launch new instance
 * }
 */
QtObject {
    id: lifecycleManager

    /**
     * @brief Current foreground app instance
     * @type {Object}
     */
    property var foregroundApp: null

    /**
     * @brief Registry of running app instances (appId -> app instance)
     * @type {Object}
     */
    property var appRegistry: ({})

    /**
     * @brief App state tracking (appId -> state object)
     * @type {Object}
     */
    property var appStates: ({})

    /**
     * @brief Registers an app instance with the lifecycle manager
     *
     * Called automatically by MApp on Component.onCompleted.
     * Apps must register to receive lifecycle events.
     *
     * @param {string} appId - Unique app identifier
     * @param {Object} appInstance - The MApp instance
     */
    function registerApp(appId, appInstance) {
        Logger.info("AppLifecycle", "━━━━━━━ registerApp() CALLED ━━━━━━━");
        Logger.info("AppLifecycle", "  appId: " + appId);
        Logger.info("AppLifecycle", "  appInstance: " + appInstance);
        Logger.info("AppLifecycle", "  appInstance.appName: " + (appInstance ? appInstance.appName : "N/A"));
        Logger.info("AppLifecycle", "  appInstance.appIcon: " + (appInstance ? appInstance.appIcon : "N/A"));

        // VALIDATION: Check if icon path matches registry/manifest
        if (appInstance && typeof MarathonAppRegistry !== 'undefined') {
            var registryInfo = MarathonAppRegistry.getApp(appId);
            if (registryInfo && registryInfo.icon && appInstance.appIcon) {
                var manifestIcon = registryInfo.icon;
                var mappIcon = appInstance.appIcon;

                Logger.info("AppLifecycle", "   Validating icon path...");
                Logger.info("AppLifecycle", "    Manifest icon: " + manifestIcon);
                Logger.info("AppLifecycle", "    MApp icon:     " + mappIcon);

                // Check if they match (allow for different path formats)
                var iconBasename = manifestIcon.split('/').pop();
                var isMatch = mappIcon.includes(iconBasename) || manifestIcon.includes(mappIcon);

                if (!isMatch) {
                    Logger.warn("AppLifecycle", "        ICON PATH MISMATCH DETECTED!     ");
                    Logger.warn("AppLifecycle", "  App: " + appId);
                    Logger.warn("AppLifecycle", "  manifest.json icon: " + manifestIcon);
                    Logger.warn("AppLifecycle", "  MApp.appIcon:       " + mappIcon);
                    Logger.warn("AppLifecycle", "  This may cause TaskModel registration to fail!");
                    Logger.warn("AppLifecycle", "  FIX: Update MApp.appIcon to match manifest.json");
                }
            }
        }

        appRegistry[appId] = appInstance;

        if (!appStates[appId]) {
            appStates[appId] = {
                appId: appId,
                isActive: false,
                isPaused: false,
                isMinimized: false,
                launchTime: Date.now(),
                lastActiveTime: 0
            };
            Logger.info("AppLifecycle", "   Created new app state for: " + appId);
        } else {
            Logger.info("AppLifecycle", "  ℹ  App state already exists for: " + appId);
        }

        // If this app was waiting to be brought to foreground, do it now
        Logger.info("AppLifecycle", "   Checking pending foreground apps: " + JSON.stringify(pendingForegroundApps));
        if (pendingForegroundApps.indexOf(appId) !== -1) {
            Logger.info("AppLifecycle", "   App WAS pending - applying foreground now!");
            var index = pendingForegroundApps.indexOf(appId);
            pendingForegroundApps.splice(index, 1);
            bringToForeground(appId);
        } else {
            Logger.info("AppLifecycle", "  ℹ  App was NOT in pending list");
        }
        Logger.info("AppLifecycle", "━━━━━━━ registerApp() COMPLETE ━━━━━━━");
    }

    /**
     * Unregister an app instance
     */
    function unregisterApp(appId) {
        Logger.info("AppLifecycle", "Unregistering app: " + appId);

        // Clean up task when app unregistered
        if (typeof TaskModel !== 'undefined') {
            var task = TaskModel.getTaskByAppId(appId);
            if (task) {
                TaskModel.closeTask(task.id);
                Logger.info("AppLifecycle", "Removed task for unregistered app: " + appId);
            }
        }

        delete appRegistry[appId];
        delete appStates[appId];
    }

    /**
     * Get app instance for preview/snapshot
     */
    function getAppInstance(appId) {
        return appRegistry[appId] || null;
    }

    /**
     * Bring app to foreground
     */
    function bringToForeground(appId) {
        Logger.info("AppLifecycle", "Bringing to foreground: " + appId);
        Logger.info("AppLifecycle", "App in registry: " + (appRegistry[appId] !== undefined));

        // Pause current foreground app
        if (foregroundApp && foregroundApp.appId !== appId) {
            if (appRegistry[foregroundApp.appId]) {
                var previousApp = appRegistry[foregroundApp.appId];
                previousApp.pause();
                previousApp.stop();  // No longer visible
            }
        }

        // Resume/start new foreground app
        if (appRegistry[appId]) {
            var app = appRegistry[appId];
            app.start();   // Becomes visible
            app.resume();  // Becomes active

            // Store full app reference, not just appId
            foregroundApp = {
                appId: appId,
                appName: app.appName || appId,
                appIcon: app.appIcon || "",
                appType: app.appType || "marathon"
            };
            Logger.info("AppLifecycle", "Set foregroundApp to: " + appId);

            if (appStates[appId]) {
                appStates[appId].isActive = true;
                appStates[appId].lastActiveTime = Date.now();
            }
        } else {
            Logger.warn("AppLifecycle", "App not in registry yet, deferring foreground");
            // App will register itself shortly, set foreground then
            pendingForegroundApps.push(appId);
        }
    }

    property var pendingForegroundApps: []

    /**
     * Restore app from task switcher
     */
    function restoreApp(appId) {
        Logger.info("AppLifecycle", "Restoring app: " + appId);

        if (appRegistry[appId]) {
            appRegistry[appId].restore();  // Calls start() + resume()
            bringToForeground(appId);
        }
    }

    /**
     * Handle system back gesture
     * Routes to current foreground app
     * @returns {bool} - true if handled, false to close app
     */
    function handleSystemBack() {
        Logger.info("AppLifecycle", "handleSystemBack() called, foregroundApp: " + (foregroundApp ? foregroundApp.appId : "null"));

        if (!foregroundApp) {
            Logger.warn("AppLifecycle", "No foreground app to handle back");
            return false;
        }

        var appId = foregroundApp.appId;
        Logger.info("AppLifecycle", "Routing back gesture to: " + appId);
        Logger.info("AppLifecycle", "App registered: " + (appRegistry[appId] !== undefined));

        if (appRegistry[appId]) {
            Logger.info("AppLifecycle", "Calling app.handleBack()");
            var handled = appRegistry[appId].handleBack();
            Logger.info("AppLifecycle", "Back handled by app: " + handled);
            return handled;
        }

        Logger.warn("AppLifecycle", "App not found in registry!");
        return false;
    }

    function handleSystemForward() {
        if (!foregroundApp) {
            return false;
        }

        var appId = foregroundApp.appId;

        if (appRegistry[appId]) {
            var handled = appRegistry[appId].handleForward();
            return handled;
        }

        return false;
    }

    /**
     * Minimize current foreground app
     */
    function minimizeForegroundApp() {
        Logger.info("AppLifecycle", "━━━━━━━ minimizeForegroundApp() CALLED ━━━━━━━");

        if (!foregroundApp) {
            Logger.warn("AppLifecycle", " No foreground app to minimize!");
            return false;
        }

        var appId = foregroundApp.appId;
        Logger.info("AppLifecycle", "📱 Minimizing app: " + appId);
        Logger.info("AppLifecycle", "  foregroundApp.appId: " + foregroundApp.appId);
        Logger.info("AppLifecycle", "  foregroundApp.appName: " + foregroundApp.appName);

        // Create task if doesn't exist (no snapshot needed - using live preview)
        if (typeof TaskModel !== 'undefined') {
            var taskExists = TaskModel.getTaskByAppId(appId) !== null;
            Logger.info("AppLifecycle", "   Checking TaskModel...");
            Logger.info("AppLifecycle", "    Task exists: " + taskExists);

            if (!taskExists) {
                if (appRegistry[appId]) {
                    var app = appRegistry[appId];
                    Logger.info("AppLifecycle", "  ➕ Creating new task...");
                    Logger.info("AppLifecycle", "    appId: " + app.appId);
                    Logger.info("AppLifecycle", "    appName: " + app.appName);
                    Logger.info("AppLifecycle", "    appIcon: " + app.appIcon);
                    Logger.info("AppLifecycle", "    appType: " + (app.appType || "marathon"));

                    TaskModel.launchTask(app.appId, app.appName, app.appIcon, app.appType || "marathon", app.surfaceId || -1);
                    Logger.info("AppLifecycle", "   Task created for: " + appId);
                } else {
                    Logger.error("AppLifecycle", "   App not in registry: " + appId);
                }
            } else {
                Logger.info("AppLifecycle", "  ℹ  Task already exists for: " + appId);
            }
        } else {
            Logger.error("AppLifecycle", "   TaskModel is undefined!");
        }

        // Hide the app
        Logger.info("AppLifecycle", "   Hiding app...");
        if (appRegistry[appId]) {
            appRegistry[appId].minimize();
            appRegistry[appId].stop();

            if (appStates[appId]) {
                appStates[appId].isMinimized = true;
                appStates[appId].isActive = false;
                Logger.info("AppLifecycle", "   App state updated: isMinimized=true, isActive=false");
            }
        } else {
            Logger.error("AppLifecycle", "   App not in registry (hide step): " + appId);
        }

        // Clear foreground but keep app alive
        Logger.info("AppLifecycle", "   Clearing foreground app");
        foregroundApp = null;

        Logger.info("AppLifecycle", "━━━━━━━ minimizeForegroundApp() COMPLETE ━━━━━━━");
        return true;
    }

    /**
     * Broadcast low memory warning to all apps
     */
    function broadcastLowMemory() {
        Logger.warn("AppLifecycle", "Broadcasting low memory warning to all apps");

        for (var appId in appRegistry) {
            if (appRegistry[appId]) {
                appRegistry[appId].handleLowMemory();
            }
        }
    }

    /**
     * Close an app
     */
    function closeApp(appId) {
        Logger.info("AppLifecycle", "Closing app: " + appId);

        // Remove from TaskModel
        if (typeof TaskModel !== 'undefined') {
            var task = TaskModel.getTaskByAppId(appId);
            if (task) {
                TaskModel.closeTask(task.id);
                Logger.info("AppLifecycle", "Removed task for closed app: " + appId);
            }
        }

        if (appRegistry[appId]) {
            appRegistry[appId].close();
        }

        if (foregroundApp && foregroundApp.appId === appId) {
            foregroundApp = null;
        }

        unregisterApp(appId);

        // CRITICAL: Tell MarathonAppLoader to clean up the cached component
        // This ensures a fresh load on next launch
        if (typeof MarathonAppLoader !== 'undefined') {
            MarathonAppLoader.unloadApp(appId);
            Logger.info("AppLifecycle", "Unloaded component from MarathonAppLoader: " + appId);
        }
    }

    /**
     * Get app state
     */
    function getAppState(appId) {
        return appStates[appId] || null;
    }

    /**
     * Check if app is running
     */
    function isAppRunning(appId) {
        return appRegistry.hasOwnProperty(appId);
    }

    /**
     * Get current foreground app ID
     */
    function getForegroundAppId() {
        return foregroundApp ? foregroundApp.appId : null;
    }
}
