pragma Singleton
import QtQuick

QtObject {
    id: desktopFileParser

    readonly property var standardPaths: ["/usr/share/applications", "/usr/local/share/applications", "~/.local/share/applications"]

    property var desktopApps: []

    signal appsDiscovered(var apps)

    Component.onCompleted: {
        if (Platform.isLinux) {
            _discoverApplications();
        }
    }

    function parseDesktopFile(filePath) {
        console.log("[DesktopFileParser] Parsing:", filePath);

        var app = {
            id: "",
            name: "",
            exec: "",
            icon: "",
            type: "Application",
            categories: [],
            desktopFile: filePath
        };

        return app;
    }

    function getInstalledApps() {
        return desktopApps;
    }

    function findAppByName(name) {
        for (var i = 0; i < desktopApps.length; i++) {
            if (desktopApps[i].name === name) {
                return desktopApps[i];
            }
        }
        return null;
    }

    function findAppById(id) {
        for (var i = 0; i < desktopApps.length; i++) {
            if (desktopApps[i].id === id) {
                return desktopApps[i];
            }
        }
        return null;
    }

    function _discoverApplications() {
        console.log("[DesktopFileParser] Discovering applications...");
    }

    function _readDesktopFile(filePath) {
        console.log("[DesktopFileParser] Reading file:", filePath);
        return "";
    }

    function _parseDesktopEntry(content) {
        var lines = content.split('\n');
        var entry = {};
        var inDesktopEntry = false;

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();

            if (line === '[Desktop Entry]') {
                inDesktopEntry = true;
                continue;
            }

            if (line.startsWith('[') && line !== '[Desktop Entry]') {
                break;
            }

            if (inDesktopEntry && line.indexOf('=') > 0) {
                var parts = line.split('=');
                var key = parts[0].trim();
                var value = parts.slice(1).join('=').trim();
                entry[key] = value;
            }
        }

        return entry;
    }
}
