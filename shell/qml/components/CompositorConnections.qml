import QtQuick
import MarathonOS.Shell

QtObject {
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
        console.warn("========== SURFACE CREATED ==========");
        console.warn("  surfaceId: " + surfaceId);
        console.warn("  surface: " + (surface ? "EXISTS" : "NULL"));
        console.warn("  xdgSurface: " + (xdgSurface ? "EXISTS" : "NULL"));
        console.warn("  pendingNativeApp: " + (root.pendingNativeApp ? root.pendingNativeApp.name : "NULL"));

        // Get app info from xdgSurface if available
        var appId = xdgSurface && xdgSurface.toplevel ? xdgSurface.toplevel.appId : "";
        var title = xdgSurface && xdgSurface.toplevel ? xdgSurface.toplevel.title : "";

        console.warn("  appId: '" + appId + "'");
        console.warn("  title: '" + title + "'");
        console.warn("  TaskModel defined: " + (typeof TaskModel !== 'undefined'));
        console.warn("  appWindow: " + (root.appWindow ? "EXISTS" : "NULL"));

        // Set properties on the surface for later use
        surface.xdgSurface = xdgSurface;
        if (xdgSurface && xdgSurface.toplevel) {
            surface.toplevel = xdgSurface.toplevel;
        }

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
                    TaskModel.updateTaskSurface(app.id, surface);
                    Logger.info("CompositorConnections", "Native app already has task, updated surface");
                }
            }

            if (root.appWindow) {
                root.appWindow.show(app.id, app.name, app.icon, "native", surface, surfaceId);
            }

            root.pendingNativeApp = null;
            return;
        }

        // Case 2: No pending app - this could be:
        //   a) A secondary window/dialog from an already-running app
        //   b) An app launched externally (e.g., from terminal)
        //   c) The main window arrived after pendingNativeApp was cleared (timing race)

        Logger.info("CompositorConnections", "Surface created without pending app - checking if it's a child window or external launch");

        // Check if this is a secondary window for an existing task (same appId)
        if (appId && typeof TaskModel !== 'undefined') {
            var existingTask = TaskModel.getTaskByAppId(appId);
            if (existingTask) {
                // This is a secondary window (dialog, popup, etc.) for an existing app
                Logger.info("CompositorConnections", "Secondary window for existing app: " + appId);

                // For dialogs/popups, we should show them in front of the main window
                // Create a popup/dialog window that floats on top
                if (root.appWindow && root.appWindow.appId === appId) {
                    // Update the appWindow to handle this secondary surface
                    // For now, just show it - the NativeAppWindow should handle multiple surfaces
                    root.appWindow.show(appId, existingTask.title, existingTask.icon, "native", surface, surfaceId);
                }
                return;
            }
        }

        // Case 3: Completely new app not launched through our UI (external launch)
        // Create a task for it using the appId/title from the surface
        if (appId) {
            Logger.info("CompositorConnections", "External app detected: " + appId);

            // Try to find app info from AppModel
            var appInfo = null;
            if (typeof AppModel !== 'undefined') {
                appInfo = AppModel.getApp(appId);
            }

            var appName = title || appId;
            var appIcon = appInfo ? appInfo.icon : "application";

            if (typeof TaskModel !== 'undefined') {
                TaskModel.launchTask(appId, appName, appIcon, "native", surfaceId, surface);
                Logger.info("CompositorConnections", "Created task for external app: " + appName);
            }

            // Show the app window
            if (root.appWindow) {
                root.appWindow.show(appId, appName, appIcon, "native", surface, surfaceId);
            }
        } else {
            Logger.warn("CompositorConnections", "Unknown surface with no appId - ignoring");
        }
    }

    function handleSurfaceDestroyed(surface, surfaceId) {
        // NOTE: Task cleanup for native apps is now handled in MarathonShell.qml using getTaskBySurfaceId()
        // This function only handles window cleanup

        // Close the visible window if it's the destroyed surface
        if (typeof UIStore !== 'undefined' && root.appWindow) {
            if (UIStore.appWindowOpen && root.appWindow.appType === "native" && root.appWindow.surfaceId === surfaceId) {
                UIStore.closeApp();
                root.appWindow.hide();
            }
        }
    }

    function handleAppClosed(pid) {
        Logger.info("CompositorConnections", "Native app process closed, PID: " + pid);
    }

    function handleAppLaunched(command, pid) {
        Logger.info("CompositorConnections", "Native app process started: " + command + " (PID: " + pid + ")");
    }

    function handlePopupCreated(surface, surfaceId, xdgSurface, parentSurface) {
        console.warn("[CompositorConnections] Popup created, surfaceId: " + surfaceId);

        // Set properties on the surface for ShellSurfaceItem
        surface.xdgSurface = xdgSurface;

        // Find which app this popup belongs to (by matching parent surface)
        var parentSurfaceId = parentSurface ? parentSurface.surfaceId : -1;
        console.warn("[CompositorConnections]   parentSurfaceId: " + parentSurfaceId);

        // For popups, we show them using the current app window
        // The popup should overlay on top of the parent native app
        if (root.appWindow && root.appWindow.appType === "native") {
            console.warn("[CompositorConnections] Showing popup in appWindow");

            // Get info from parent task if available
            var appId = root.appWindow.appId;
            var appName = "Popup";
            var appIcon = root.appWindow.appIcon || "application";

            // Show the popup as a secondary surface in the app window
            root.appWindow.show(appId, appName, appIcon, "native", surface, surfaceId);
        } else {
            console.warn("[CompositorConnections] No active native app window, showing popup as standalone");

            // If no app window is open, create a task for the popup
            if (typeof TaskModel !== 'undefined') {
                TaskModel.launchTask("popup-" + surfaceId, "Dialog", "dialog-info", "native", surfaceId, surface);
            }

            if (root.appWindow) {
                root.appWindow.show("popup-" + surfaceId, "Dialog", "dialog-info", "native", surface, surfaceId);
            }
        }
    }
}
