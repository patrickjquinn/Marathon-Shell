pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root

    property var compositor: null
    property var appWindow: null
    property var pendingNativeApp: null
    property var launchingApps: ({})  // Track apps currently launching

    // Signal for launch events
    signal appLaunchStarted(string appId, string appName)
    signal appLaunchCompleted(string appId, string appName)
    signal appLaunchFailed(string appId, string appName, string error)
    signal appLaunchProgress(string appId, int percent)

    function launchApp(app, compositorRef, appWindowRef) {
        // Resolve references
        var comp = compositorRef || root.compositor;
        var win = appWindowRef || root.appWindow;

        // Handle string input (appId)
        if (typeof app === 'string') {
            var appId = app;
            Logger.info("AppLaunchService", "Looking up app by ID: " + appId);

            if (typeof AppModel !== 'undefined') {
                var appObj = AppModel.getApp(appId);
                if (appObj) {
                    app = appObj;
                    Logger.info("AppLaunchService", "Found app in AppModel: " + app.name);
                } else {
                    // Fallback: Check if it's a running task (e.g. launched externally)
                    if (typeof TaskModel !== 'undefined') {
                        var task = TaskModel.getTaskByAppId(appId);
                        if (task) {
                            Logger.info("AppLaunchService", "Found running task for: " + appId);
                            // Create a temporary app object from task info
                            app = {
                                id: appId,
                                name: task.title || appId,
                                icon: task.icon || "",
                                type: task.appType || "native",
                                exec: "" // Not needed for bringing to foreground
                            };
                        } else {
                            Logger.error("AppLaunchService", "App not found in AppModel or TaskModel: " + appId);
                            root.appLaunchFailed(appId, "Unknown", "App not found");
                            return false;
                        }
                    } else {
                        Logger.error("AppLaunchService", "App not found in AppModel: " + appId);
                        root.appLaunchFailed(appId, "Unknown", "App not found");
                        return false;
                    }
                }
            } else {
                Logger.error("AppLaunchService", "AppModel not available");
                return false;
            }
        }

        Logger.info("AppLaunchService", "Launching app: " + app.name + " (type: " + app.type + ")");

        // Validation
        if (!win) {
            Logger.error("AppLaunchService", "appWindow reference not provided (and root.appWindow is null)");
            root.appLaunchFailed(app.id, app.name, "No app window reference");
            return false;
        }

        if (!app || !app.id || !app.name) {
            Logger.error("AppLaunchService", "Invalid app object");
            root.appLaunchFailed("", "", "Invalid app object");
            return false;
        }

        // Check if already launching
        if (launchingApps[app.id]) {
            Logger.warn("AppLaunchService", "App already launching: " + app.name);
            return false;
        }

        // Mark as launching
        launchingApps[app.id] = true;
        root.appLaunchStarted(app.id, app.name);

        if (app.type === "native") {
            return launchNativeApp(app, comp, win);
        } else {
            return launchMarathonApp(app, comp, win);
        }
    }

    function launchNativeApp(app, compositorRef, appWindowRef) {
        if (!compositorRef) {
            Logger.error("AppLaunchService", "Cannot launch native app - compositor not available");
            delete launchingApps[app.id];
            root.appLaunchFailed(app.id, app.name, "Compositor not available");
            return false;
        }

        root.pendingNativeApp = app;
        root.compositor = compositorRef;

        try {
            UIStore.openApp(app.id, app.name, app.icon);
            appWindowRef.show(app.id, app.name, app.icon, "native", null, -1);
            Logger.info("AppLaunchService", "Showing splash screen for native app: " + app.name);
            root.appLaunchProgress(app.id, 50);

            // Launch native app via compositor
            compositorRef.launchApp(app.exec);

            // Native apps report their own readiness via Wayland protocol
            // For now, mark as completed immediately after launch
            delete launchingApps[app.id];
            root.appLaunchCompleted(app.id, app.name);
            Logger.info("AppLaunchService", "Native app launched: " + app.name);
            return true;
        } catch (error) {
            Logger.error("AppLaunchService", "Failed to launch native app: " + error);
            delete launchingApps[app.id];
            root.appLaunchFailed(app.id, app.name, "Launch failed: " + error);
            return false;
        }
    }

    function closeNativeApp(surfaceId) {
        if (!root.compositor) {
            Logger.error("AppLaunchService", "Cannot close native app - compositor not available");
            return;
        }

        Logger.info("AppLaunchService", "Closing native app with surfaceId: " + surfaceId);
        root.compositor.closeWindow(surfaceId);
    }

    function launchMarathonApp(app, compositorRef, appWindowRef) {
        // Check if app is already running
        if (typeof AppLifecycleManager !== 'undefined' && AppLifecycleManager.isAppRunning(app.id)) {
            Logger.info("AppLaunchService", "App already running, bringing to foreground: " + app.name);

            try {
                // Bring app to foreground (updates lifecycle state)
                AppLifecycleManager.bringToForeground(app.id);

                // CRITICAL: Also restore the app window (show it)
                // This is what task switcher does - we need to do the same
                if (typeof UIStore !== 'undefined') {
                    UIStore.restoreApp(app.id, app.name, app.icon);
                }

                delete launchingApps[app.id];
                root.appLaunchCompleted(app.id, app.name);
                return true;
            } catch (error) {
                Logger.error("AppLaunchService", "Failed to bring app to foreground: " + error);
                delete launchingApps[app.id];
                root.appLaunchFailed(app.id, app.name, "Failed to bring to foreground: " + error);
                return false;
            }
        }

        try {
            UIStore.openApp(app.id, app.name, app.icon);
            root.appLaunchProgress(app.id, 30);

            // This internally calls MarathonAppLoader.loadAppAsync (via appWindowRef.show)
            appWindowRef.show(app.id, app.name, app.icon, app.type);
            root.appLaunchProgress(app.id, 60);

            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.bringToForeground(app.id);
            }

            // Mark as completed
            // TODO: In future, wait for actual app ready signal from MApp
            delete launchingApps[app.id];
            root.appLaunchProgress(app.id, 100);
            root.appLaunchCompleted(app.id, app.name);
            Logger.info("AppLaunchService", "Marathon app launched: " + app.name);
            return true;
        } catch (error) {
            Logger.error("AppLaunchService", "Failed to launch Marathon app: " + error);
            delete launchingApps[app.id];
            root.appLaunchFailed(app.id, app.name, "Launch failed: " + error);
            return false;
        }
    }

    function launchFromSearch(result, compositorRef, appWindowRef) {
        Logger.info("AppLaunchService", "Launching from search: " + result.name + " (type: " + result.type + ")");

        // Use main launch function for consistency
        return launchApp(result, compositorRef, appWindowRef);
    }

    function isAppLaunching(appId) {
        return launchingApps[appId] === true;
    }

    function cancelLaunch(appId) {
        if (launchingApps[appId]) {
            delete launchingApps[appId];
            Logger.info("AppLaunchService", "Cancelled launch for: " + appId);
            return true;
        }
        return false;
    }
}
