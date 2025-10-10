pragma Singleton
import QtQuick

QtObject {
    id: wallpaperStore
    
    property string path: "qrc:/wallpapers/resources/wallpapers/wallpaper.jpg"
    property bool isDark: true
    
    property var wallpapers: [
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper.jpg", isDark: true },
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper2.jpg", isDark: true },
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper3.jpg", isDark: true },
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper4.jpg", isDark: false },
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper5.jpg", isDark: true },
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper6.jpg", isDark: false },
        { path: "qrc:/wallpapers/resources/wallpapers/wallpaper7.jpg", isDark: true }
    ]
    
    function setWallpaper(newPath, newIsDark) {
        path = newPath
        isDark = newIsDark
    }
}

