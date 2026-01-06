pragma Singleton
import QtQuick

QtObject {
    id: wallpaperStore

    // NOTE: Do NOT bind directly to SettingsManagerCpp.wallpaperPath.
    // We want SettingsManagerCpp to be the source of truth, but the store must remain writable
    // (Settings app sets wallpapers). Direct bindings + writebacks create binding loops.
    property string currentWallpaper: "qrc:/wallpapers/wallpaper.jpg"
    property string path: currentWallpaper
    property bool isDark: true
    property var wallpapers: [
        {
            "name": "Gradient 1",
            "path": asset("wallpapers/wallpaper.jpg", "qrc:/wallpapers/wallpaper.jpg"),
            "isDark": true
        },
        {
            "name": "Gradient 2",
            "path": asset("wallpapers/wallpaper2.jpg", "qrc:/wallpapers/wallpaper2.jpg"),
            "isDark": true
        },
        {
            "name": "Gradient 3",
            "path": asset("wallpapers/wallpaper3.jpg", "qrc:/wallpapers/wallpaper3.jpg"),
            "isDark": true
        },
        {
            "name": "Gradient 4",
            "path": asset("wallpapers/wallpaper4.jpg", "qrc:/wallpapers/wallpaper4.jpg"),
            "isDark": false
        },
        {
            "name": "Gradient 5",
            "path": asset("wallpapers/wallpaper5.jpg", "qrc:/wallpapers/wallpaper5.jpg"),
            "isDark": true
        },
        {
            "name": "Gradient 6",
            "path": asset("wallpapers/wallpaper6.jpg", "qrc:/wallpapers/wallpaper6.jpg"),
            "isDark": false
        },
        {
            "name": "Gradient 7",
            "path": asset("wallpapers/wallpaper7.jpg", "qrc:/wallpapers/wallpaper7.jpg"),
            "isDark": true
        },
        {
            "name": "Gradient 8",
            "path": asset("wallpapers/wallpaper8.jpg", "qrc:/wallpapers/wallpaper8.jpg"),
            "isDark": true
        }
    ]

    function asset(rel, qrcFallback) {
        if (typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp && SettingsManagerCpp.assetUrl)
            return SettingsManagerCpp.assetUrl(rel);

        return qrcFallback;
    }

    function setWallpaper(newPath, newIsDark) {
        if (!newPath || newPath === currentWallpaper) {
            // Still update dark flag if the caller provided it (e.g., same wallpaper tapped).
            if (newIsDark !== undefined)
                isDark = newIsDark;

            return;
        }
        currentWallpaper = newPath;
        if (newIsDark !== undefined)
            isDark = newIsDark;

        // Persist immediately via SettingsManager (in-shell or runner proxy).
        if (typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp && SettingsManagerCpp.wallpaperPath !== newPath)
            SettingsManagerCpp.wallpaperPath = newPath;
    }

    onCurrentWallpaperChanged: {
        Logger.info("WallpaperStore", "Wallpaper changed to: " + currentWallpaper);
        for (var i = 0; i < wallpapers.length; i++) {
            if (wallpapers[i].path === currentWallpaper) {
                isDark = wallpapers[i].isDark;
                break;
            }
        }
    }
    Component.onCompleted: {
        if (typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp && SettingsManagerCpp.wallpaperPath)
            currentWallpaper = SettingsManagerCpp.wallpaperPath;

        // Keep store in sync with SettingsManager changes coming from elsewhere (e.g. runner → DBus).
        if (typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp && SettingsManagerCpp.wallpaperPathChanged)
            SettingsManagerCpp.wallpaperPathChanged.connect(function () {
                if (SettingsManagerCpp && SettingsManagerCpp.wallpaperPath && currentWallpaper !== SettingsManagerCpp.wallpaperPath)
                    currentWallpaper = SettingsManagerCpp.wallpaperPath;
            });
    }
}
