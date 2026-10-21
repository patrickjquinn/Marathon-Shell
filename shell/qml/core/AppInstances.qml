pragma Singleton
import QtQuick
import MarathonOS.Shell

// The app instances the shell draws itself: Tasks' lifecycle commands
// (pause, stop, start, resume, restore, minimize, close, handleLowMemory)
// reach them here.
QtObject {
    id: root

    property var instances: ({})

    readonly property Connections commands: Connections {
        function onAppCommand(appId, command) {
            const instance = root.instances[appId];
            if (instance && typeof instance[command] === "function")
                instance[command]();
        }

        function onAppUnregistered(appId) {
            delete root.instances[appId];
        }

        target: Tasks
    }

    function register(appId, instance) {
        instances[appId] = instance;
        Tasks.registerApp(appId, {
            "appName": instance.appName || "",
            "appIcon": instance.appIcon || "",
            "appType": instance.appType || "",
            "isNative": instance.isNative === true,
            "surfaceId": instance.surfaceId !== undefined ? instance.surfaceId : -1
        });
    }

    function unregister(appId) {
        Tasks.unregisterApp(appId);
    }

    function get(appId) {
        return instances[appId] || null;
    }
}
