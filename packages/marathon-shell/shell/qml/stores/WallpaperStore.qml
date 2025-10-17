pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: wallpaperStore
    
    property string path: "qrc:/wallpapers/resources/wallpapers/marathon-logo.jpg"
    property string currentWallpaper: path
    property bool isDark: false
    
    property var wallpapers: [
        { name: "Marathon Logo", path: "qrc:/wallpapers/resources/wallpapers/marathon-logo.jpg", isDark: false },
        { name: "Gradient 1", path: "qrc:/wallpapers/resources/wallpapers/wallpaper.jpg", isDark: true },
        { name: "Gradient 2", path: "qrc:/wallpapers/resources/wallpapers/wallpaper2.jpg", isDark: true },
        { name: "Gradient 3", path: "qrc:/wallpapers/resources/wallpapers/wallpaper3.jpg", isDark: true },
        { name: "Gradient 4", path: "qrc:/wallpapers/resources/wallpapers/wallpaper4.jpg", isDark: false },
        { name: "Gradient 5", path: "qrc:/wallpapers/resources/wallpapers/wallpaper5.jpg", isDark: true },
        { name: "Gradient 6", path: "qrc:/wallpapers/resources/wallpapers/wallpaper6.jpg", isDark: false },
        { name: "Gradient 7", path: "qrc:/wallpapers/resources/wallpapers/wallpaper7.jpg", isDark: true }
    ]
    
    onCurrentWallpaperChanged: {
        path = currentWallpaper
        Logger.info("WallpaperStore", "Wallpaper changed to: " + currentWallpaper)
        
        for (var i = 0; i < wallpapers.length; i++) {
            if (wallpapers[i].path === currentWallpaper) {
                isDark = wallpapers[i].isDark
                break
            }
        }
    }
    
    function setWallpaper(newPath, newIsDark) {
        currentWallpaper = newPath
        path = newPath
        isDark = newIsDark
    }
}

