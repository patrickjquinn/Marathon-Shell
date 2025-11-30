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
        Logger.info("CompositorConnections", "Native app surface created, surfaceId: " + surfaceId);

        if (!root.pendingNativeApp) {
            return;
        }

        var app = root.pendingNativeApp;
        Logger.info("CompositorConnections", "Surface connected for: " + app.name + " (surfaceId: " + surfaceId + ")");

        surface.xdgSurface = xdgSurface;
        surface.toplevel = xdgSurface.toplevel;

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
}
