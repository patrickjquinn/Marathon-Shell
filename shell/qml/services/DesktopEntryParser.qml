pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: desktopEntryParser

    property var nativeApps: []
    property bool isScanning: false

    signal scanComplete(int count)
    signal appFound(var appInfo)

    function scanDesktopEntries() {
        Logger.info("DesktopEntryParser", "Scanning for .desktop files");
        isScanning = true;
        nativeApps = [];

        var searchPaths = ["/usr/share/applications", "/usr/local/share/applications", "~/.local/share/applications"];

        Logger.info("DesktopEntryParser", "Search paths: " + JSON.stringify(searchPaths));

        scanTimer.start();
    }

    function parseDesktopEntry(content, fileName) {
        Logger.debug("DesktopEntryParser", "Parsing: " + fileName);

        var lines = content.split('\n');
        var inDesktopEntry = false;
        var app = {
            id: "",
            name: "",
            comment: "",
            icon: "",
            exec: "",
            terminal: false,
            categories: [],
            type: "native",
            desktopFile: fileName,
            noDisplay: false,
            hidden: false
        };

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();

            if (line === '[Desktop Entry]') {
                inDesktopEntry = true;
                continue;
            }

            if (line.startsWith('[') && line.endsWith(']')) {
                inDesktopEntry = false;
                continue;
            }

            if (!inDesktopEntry || line.length === 0 || line.startsWith('#')) {
                continue;
            }

            var parts = line.split('=');
            if (parts.length < 2)
                continue;
            var key = parts[0].trim();
            var value = parts.slice(1).join('=').trim();

            switch (key) {
            case 'Name':
                app.name = value;
                break;
            case 'Comment':
            case 'GenericName':
                if (!app.comment)
                    app.comment = value;
                break;
            case 'Icon':
                app.icon = resolveIconPath(value);
                break;
            case 'Exec':
                app.exec = cleanExecLine(value);
                break;
            case 'Terminal':
                app.terminal = (value.toLowerCase() === 'true');
                break;
            case 'Categories':
                app.categories = value.split(';').filter(c => c.length > 0);
                break;
            case 'NoDisplay':
                app.noDisplay = (value.toLowerCase() === 'true');
                break;
            case 'Hidden':
                app.hidden = (value.toLowerCase() === 'true');
                break;
            case 'Type':
                if (value !== 'Application') {
                    return null;
                }
                break;
            }
        }

        if (!app.name || !app.exec || app.noDisplay || app.hidden) {
            return null;
        }

        app.id = fileName.replace('.desktop', '');

        return app;
    }

    function resolveIconPath(iconName) {
        if (!iconName)
            return "qrc:/images/icons/lucide/grid.svg";

        if (iconName.startsWith('/')) {
            return "file://" + iconName;
        }

        if (iconName.endsWith('.svg') || iconName.endsWith('.png') || iconName.endsWith('.xpm')) {
            return "file://" + iconName;
        }

        var iconSearchPaths = ["/usr/share/pixmaps/", "/usr/share/icons/hicolor/48x48/apps/", "/usr/share/icons/hicolor/scalable/apps/", "~/.local/share/icons/"];

        for (var i = 0; i < iconSearchPaths.length; i++) {
            var testPaths = [iconSearchPaths[i] + iconName + ".svg", iconSearchPaths[i] + iconName + ".png", iconSearchPaths[i] + iconName];

            for (var j = 0; j < testPaths.length; j++) {
                return "file://" + testPaths[j];
            }
        }

        return "qrc:/images/icons/lucide/grid.svg";
    }

    function cleanExecLine(exec) {
        exec = exec.replace(/%[fFuUdDnNickvm]/g, '');
        exec = exec.trim();
        return exec;
    }

    function getApp(appId) {
        for (var i = 0; i < nativeApps.length; i++) {
            if (nativeApps[i].id === appId) {
                return nativeApps[i];
            }
        }
        return null;
    }

    function getCategoryApps(category) {
        var filtered = [];
        for (var i = 0; i < nativeApps.length; i++) {
            if (nativeApps[i].categories.indexOf(category) !== -1) {
                filtered.push(nativeApps[i]);
            }
        }
        return filtered;
    }

    property Timer scanTimer: Timer {
        interval: 100
        running: false
        repeat: false
        onTriggered: {
            if (typeof DesktopFileParserCpp === 'undefined') {
                Logger.warn("DesktopEntryParser", "C++ parser not available, using empty list");
                nativeApps = [];
                isScanning = false;
                scanComplete(0);
                return;
            }

            var searchPaths = ["/usr/share/applications", "/usr/local/share/applications", "~/.local/share/applications"];

            var apps = DesktopFileParserCpp.scanApplications(searchPaths);
            nativeApps = apps;
            isScanning = false;

            Logger.info("DesktopEntryParser", "Scan complete. Found " + nativeApps.length + " native apps");
            scanComplete(nativeApps.length);

            for (var i = 0; i < nativeApps.length; i++) {
                Logger.debug("DesktopEntryParser", "Found app: " + nativeApps[i].name + " (icon: " + nativeApps[i].icon + ")");
                appFound(nativeApps[i]);
            }
        }
    }

    Component.onCompleted: {
        Logger.info("DesktopEntryParser", "Desktop entry parser initialized");
        scanDesktopEntries();
    }
}
