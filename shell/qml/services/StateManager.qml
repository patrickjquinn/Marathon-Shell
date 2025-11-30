pragma Singleton
import QtQuick
import Qt.labs.settings

Item {
    id: root

    property var runningApps: ({})
    property var appStates: ({})

    readonly property Settings settings: Settings {
        category: "AppState"

        property string runningAppIds: ""
        property string appStateData: ""
    }

    readonly property Timer autoSaveTimer: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.saveAllStates()
    }

    function registerApp(appId: string, isVisible: bool) {
        const timestamp = Date.now();
        runningApps[appId] = {
            appId: appId,
            isVisible: isVisible,
            timestamp: timestamp
        };

        console.log("StateManager: Registered app", appId, "visible:", isVisible);
    }

    function unregisterApp(appId: string) {
        if (runningApps[appId]) {
            delete runningApps[appId];
            console.log("StateManager: Unregistered app", appId);
        }
    }

    function updateAppVisibility(appId: string, isVisible: bool) {
        if (runningApps[appId]) {
            runningApps[appId].isVisible = isVisible;
            runningApps[appId].timestamp = Date.now();
        }
    }

    function saveAppState(appId: string, state: string) {
        appStates[appId] = {
            state: state,
            timestamp: Date.now()
        };

        console.log("StateManager: Saved state for", appId, ":", state);
    }

    function saveAllStates() {
        try {
            const appIdArray = Object.keys(runningApps);
            settings.runningAppIds = JSON.stringify(appIdArray);
            settings.appStateData = JSON.stringify(appStates);
        } catch (e) {
            console.error("StateManager: Failed to save states:", e);
        }
    }

    function restoreStates() {
        try {
            if (settings.runningAppIds) {
                const appIds = JSON.parse(settings.runningAppIds);
                console.log("StateManager: Found", appIds.length, "running apps to restore");
                return appIds;
            }
        } catch (e) {
            console.error("StateManager: Failed to restore states:", e);
        }
        return [];
    }

    function getAppState(appId: string) {
        return appStates[appId] || null;
    }

    function clearAppState(appId: string) {
        if (appStates[appId]) {
            delete appStates[appId];
        }
    }

    function clearAllStates() {
        runningApps = {};
        appStates = {};
        settings.runningAppIds = "";
        settings.appStateData = "";
        console.log("StateManager: Cleared all states");
    }

    Component.onCompleted: {
        console.log("StateManager: Initialized with auto-save every 5 seconds");
    }
}
