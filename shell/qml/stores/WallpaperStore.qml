pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: wallpaperStore

    property string path: "qrc:/wallpapers/wallpaper.jpg"
    property string currentWallpaper: "qrc:/wallpapers/wallpaper.jpg"
    property bool isDark: true

    property var wallpapers: [
        {
            name: "Gradient 1",
            path: "qrc:/wallpapers/wallpaper.jpg",
            isDark: true
        },
        {
            name: "Gradient 2",
            path: "qrc:/wallpapers/wallpaper2.jpg",
            isDark: true
        },
        {
            name: "Gradient 3",
            path: "qrc:/wallpapers/wallpaper3.jpg",
            isDark: true
        },
        {
            name: "Gradient 4",
            path: "qrc:/wallpapers/wallpaper4.jpg",
            isDark: false
        },
        {
            name: "Gradient 5",
            path: "qrc:/wallpapers/wallpaper5.jpg",
            isDark: true
        },
        {
            name: "Gradient 6",
            path: "qrc:/wallpapers/wallpaper6.jpg",
            isDark: false
        },
        {
            name: "Gradient 7",
            path: "qrc:/wallpapers/wallpaper7.jpg",
            isDark: true
        },
        {
            name: "Gradient 8",
            path: "qrc:/wallpapers/wallpaper8.jpg",
            isDark: true
        }
    ]

    onCurrentWallpaperChanged: {
        path = currentWallpaper;
        Logger.info("WallpaperStore", "Wallpaper changed to: " + currentWallpaper);

        for (var i = 0; i < wallpapers.length; i++) {
            if (wallpapers[i].path === currentWallpaper) {
                isDark = wallpapers[i].isDark;
                break;
            }
        }
    }

    function setWallpaper(newPath, newIsDark) {
        currentWallpaper = newPath;
        path = newPath;
        isDark = newIsDark;
    }
}
