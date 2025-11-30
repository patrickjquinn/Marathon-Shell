pragma Singleton
import QtQuick

QtObject {
    id: windowManager

    readonly property bool isWaylandCompositor: false

    property var windows: []
    property string activeWindow: ""

    signal windowCreated(string windowId, var surface)
    signal windowDestroyed(string windowId)
    signal windowFocused(string windowId)
    signal windowMinimized(string windowId)
    signal windowRestored(string windowId)

    function registerWindow(appId, surface) {
        console.log("[WindowManager] Registering window for app:", appId);

        var windowId = _generateWindowId(appId);

        var window = {
            id: windowId,
            appId: appId,
            surface: surface,
            geometry: {
                x: 0,
                y: 0,
                width: 720,
                height: 1280
            },
            state: "normal",
            timestamp: Date.now()
        };

        windows.push(window);
        windowsChanged();
        windowCreated(windowId, surface);

        return windowId;
    }

    function unregisterWindow(windowId) {
        console.log("[WindowManager] Unregistering window:", windowId);

        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === windowId) {
                windows.splice(i, 1);
                windowsChanged();
                windowDestroyed(windowId);

                if (activeWindow === windowId) {
                    activeWindow = "";
                }
                return;
            }
        }
    }

    function focusWindow(windowId) {
        console.log("[WindowManager] Focusing window:", windowId);
        activeWindow = windowId;
        windowFocused(windowId);
    }

    function minimizeWindow(windowId) {
        console.log("[WindowManager] Minimizing window:", windowId);

        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === windowId) {
                windows[i].state = "minimized";
                windowsChanged();
                windowMinimized(windowId);
                return;
            }
        }
    }

    function restoreWindow(windowId) {
        console.log("[WindowManager] Restoring window:", windowId);

        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === windowId) {
                windows[i].state = "normal";
                windowsChanged();
                windowRestored(windowId);
                return;
            }
        }
    }

    function getWindowForApp(appId) {
        for (var i = 0; i < windows.length; i++) {
            if (windows[i].appId === appId) {
                return windows[i];
            }
        }
        return null;
    }

    function _generateWindowId(appId) {
        return appId + "_" + Date.now();
    }

    function captureWindowSnapshot(windowId) {
        console.log("[WindowManager] Capturing snapshot for:", windowId);
        return null;
    }
}
