import MarathonOS.Shell
import MarathonUI.Core
import QtQuick

QtObject {
    // NOTE: Task cleanup for native apps is now handled in MarathonShell.qml using getTaskBySurfaceId()
    // This function only handles window cleanup
    // Case 2: No pending app - this could be:
    //   a) A secondary window/dialog from an already-running app
    //   b) An app launched externally (e.g., from terminal)
    //   c) The main window arrived after pendingNativeApp was cleared (timing race)
    // Only look up by real appId
    // Update the appWindow to handle this secondary surface
    // For now, just show it - the NativeAppWindow should handle multiple surfaces

    id: root

    property var compositor: null
    property var appWindow: null
    property var pendingNativeApp: null

    function setupConnections(compositorRef, appWindowRef, pendingNativeAppRef) {
        root.compositor = compositorRef;
        root.appWindow = appWindowRef;
        root.pendingNativeApp = pendingNativeAppRef;
    }

    function handleSurfaceCreated(surface, surfaceId, xdgSurface) {
        // Reduced verbosity logging
        Logger.info("CompositorConnections", "Surface created: " + surfaceId + (root.pendingNativeApp ? " (Pending App: " + root.pendingNativeApp.name + ")" : ""));

        // Get app info from xdgSurface if available
        var appId = xdgSurface && xdgSurface.toplevel ? xdgSurface.toplevel.appId : "";
        var title = xdgSurface && xdgSurface.toplevel ? xdgSurface.toplevel.title : "";

        // Set properties on the surface for later use
        surface.xdgSurface = xdgSurface;
        if (xdgSurface && xdgSurface.toplevel)
            surface.toplevel = xdgSurface.toplevel;

        // Case 1: We launched this app and it's the pending one
        if (root.pendingNativeApp) {
            var app = root.pendingNativeApp;
            Logger.info("CompositorConnections", "Surface matched pending app: " + app.name + " (surfaceId: " + surfaceId + ")");
            if (typeof TaskModel !== 'undefined') {
                var existingTask = TaskModel.getTaskByAppId(app.id);
                if (!existingTask) {
                    TaskModel.launchTask(app.id, app.name, app.icon, "native", surfaceId, surface);
                    Logger.info("CompositorConnections", "Added native app to TaskModel: " + app.name + " (surfaceId: " + surfaceId + ")");
                } else {
                    // Task exists (may have been created before surface arrived) - update ALL native info
                    TaskModel.updateTaskNativeInfo(app.id, surfaceId, surface);
                    Logger.info("CompositorConnections", "Native app already has task, updated native info (type, surfaceId, surface)");
                }
            }
            if (root.appWindow)
                root.appWindow.show(app.id, app.name, app.icon, "native", surface, surfaceId);

            root.pendingNativeApp = null;
            return;
        }
        Logger.info("CompositorConnections", "Surface created without pending app - checking if it's a child window or external launch");
        // Check if this is a secondary window for an existing task (same appId)
        if (appId && typeof TaskModel !== 'undefined') {
            var existingTask = TaskModel.getTaskByAppId(appId);
            if (existingTask) {
                // This is a secondary window (dialog, popup, etc.) for an existing app
                Logger.info("CompositorConnections", "Secondary window for existing app: " + appId);
                // For dialogs/popups, we should show them in front of the main window
                // Create a popup/dialog window that floats on top
                if (root.appWindow && root.appWindow.appId === appId)
                    root.appWindow.show(appId, existingTask.title, existingTask.icon, "native", surface, surfaceId);

                return;
            }
        }
        // Case 3: Completely new app not launched through our UI (external launch)
        // Create a task for it using the appId/title from the surface
        // FALLBACK: If appId is missing but we have a title, use that as ID to ensure it shows up
        var effectiveAppId = appId;
        if (!effectiveAppId && title) {
            effectiveAppId = "native-app-" + title.replace(/[^a-zA-Z0-9]/g, "-").toLowerCase();
            Logger.warn("CompositorConnections", "App has no appId, generating from title: " + effectiveAppId);
        } else if (!effectiveAppId) {
            effectiveAppId = "native-surface-" + surfaceId;
            Logger.warn("CompositorConnections", "App has no appId or title, generic ID: " + effectiveAppId);
        }
        if (effectiveAppId) {
            Logger.info("CompositorConnections", "External app detected: " + effectiveAppId);
            // Try to find app info from AppModel
            var appInfo = null;
            if (appId && typeof AppModel !== 'undefined')
                appInfo = AppModel.getApp(appId);

            var appName = title || appId || ("Native App " + surfaceId);
            // Fix for fuzzy icons: Prefer appId (theme lookup) over specific file paths from AppModel
            // AppModel often returns 48x48 paths which look bad on splash screens
            var appIcon = appId || (appInfo ? appInfo.icon : "application-x-executable");
            if (typeof TaskModel !== 'undefined') {
                TaskModel.launchTask(effectiveAppId, appName, appIcon, "native", surfaceId, surface);
                Logger.info("CompositorConnections", "Created task for external app: " + appName + " icon: " + appIcon);
            }
            // Show the app window
            if (root.appWindow)
                root.appWindow.show(effectiveAppId, appName, appIcon, "native", surface, surfaceId);
        } else {
            // Should be unreachable now due to fallback
            Logger.warn("CompositorConnections", "Unknown surface could not be handled");
        }
    }

    function handleSurfaceDestroyed(surface, surfaceId) {
        // CRITICAL: Do NOT call UIStore.closeApp() here!
        // Apps like Chromium destroy their surface during swipe-to-task-switcher,
        // showing restore dialogs, or other transitions - but the process is still running.
        // Only handleAppClosed() should close the app when the process actually terminates.
        // Calling closeApp() here causes a timing bug where appWindowOpen becomes false
        // before the gesture handler runs, breaking the minimize flow.
        Logger.info("CompositorConnections", "Surface destroyed for surfaceId: " + surfaceId + " (NOT closing app - process may still be running)");
    }

    function handleAppClosed(pid) {
        Logger.info("CompositorConnections", "Native app process closed, PID: " + pid);
    }

    function handleAppLaunched(command, pid) {
        Logger.info("CompositorConnections", "Native app process started: " + command + " (PID: " + pid + ")");
    }
}
