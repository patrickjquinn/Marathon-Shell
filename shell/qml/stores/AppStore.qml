pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: appStore

    property var marathonApps: [
        {
            id: "phone",
            name: "Phone",
            icon: "qrc:/images/phone.svg",
            type: "marathon"
        },
        {
            id: "messages",
            name: "Messages",
            icon: "qrc:/images/messages.svg",
            type: "marathon"
        },
        {
            id: "camera",
            name: "Camera",
            icon: "qrc:/images/camera.svg",
            type: "marathon"
        },
        {
            id: "gallery",
            name: "Gallery",
            icon: "qrc:/images/gallery.svg",
            type: "marathon"
        },
        {
            id: "music",
            name: "Music",
            icon: "qrc:/images/music.svg",
            type: "marathon"
        },
        {
            id: "calendar",
            name: "Calendar",
            icon: "qrc:/images/calendar.svg",
            type: "marathon"
        },
        {
            id: "clock",
            name: "Clock",
            icon: "qrc:/images/clock.svg",
            type: "marathon"
        },
        {
            id: "maps",
            name: "Maps",
            icon: "qrc:/images/maps.svg",
            type: "marathon"
        },
        {
            id: "notes",
            name: "Notes",
            icon: "qrc:/images/notes.svg",
            type: "marathon"
        },
        {
            id: "settings",
            name: "Settings",
            icon: "qrc:/images/settings.svg",
            type: "marathon"
        }
    ]

    property var nativeApps: []

    property var apps: []

    // Helper function to get app metadata by ID
    function getApp(appId) {
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].id === appId) {
                return apps[i];
            }
        }
        return null;
    }

    // Get app name by ID
    function getAppName(appId) {
        var app = getApp(appId);
        return app ? app.name : appId;
    }

    // Get app icon by ID
    function getAppIcon(appId) {
        var app = getApp(appId);
        return app ? app.icon : "";
    }

    // Check if app is Marathon app
    function isInternalApp(appId) {
        var app = getApp(appId);
        return app ? (app.type === "marathon") : true;
    }

    // Check if app is native Wayland app
    function isNativeApp(appId) {
        var app = getApp(appId);
        return app ? (app.type === "native") : false;
    }

    // Merge Marathon apps and native apps
    function refreshAppList() {
        var merged = [];

        for (var i = 0; i < marathonApps.length; i++) {
            merged.push(marathonApps[i]);
        }

        for (var j = 0; j < nativeApps.length; j++) {
            merged.push(nativeApps[j]);
        }

        apps = merged;
        Logger.info("AppStore", "App list refreshed. Total: " + apps.length + " (Marathon: " + marathonApps.length + ", Native: " + nativeApps.length + ")");
    }

    // Listen for native apps from DesktopEntryParser
    property Connections desktopEntryConnection: Connections {
        target: typeof DesktopEntryParser !== 'undefined' ? DesktopEntryParser : null

        function onScanComplete(count) {
            Logger.info("AppStore", "Native apps scan complete: " + count + " apps");
            nativeApps = DesktopEntryParser.nativeApps;
            refreshAppList();
        }
    }

    Component.onCompleted: {
        Logger.info("AppStore", "AppStore initialized");
        refreshAppList();
    }
}
