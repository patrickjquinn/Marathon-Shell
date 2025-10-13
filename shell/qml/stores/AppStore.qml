pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: appStore
    
    // App catalog - all available apps
    property var apps: [
        { id: "phone", name: "Phone", icon: "qrc:/images/phone.svg", exec: "", isInternal: true },
        { id: "messages", name: "Messages", icon: "qrc:/images/messages.svg", exec: "", isInternal: true },
        { id: "browser", name: "Browser", icon: "qrc:/images/browser.svg", exec: "", isInternal: false, desktopFile: "/usr/share/applications/firefox.desktop" },
        { id: "camera", name: "Camera", icon: "qrc:/images/camera.svg", exec: "", isInternal: true },
        { id: "gallery", name: "Gallery", icon: "qrc:/images/gallery.svg", exec: "", isInternal: true },
        { id: "music", name: "Music", icon: "qrc:/images/music.svg", exec: "", isInternal: true },
        { id: "calendar", name: "Calendar", icon: "qrc:/images/calendar.svg", exec: "", isInternal: true },
        { id: "clock", name: "Clock", icon: "qrc:/images/clock.svg", exec: "", isInternal: true },
        { id: "maps", name: "Maps", icon: "qrc:/images/maps.svg", exec: "", isInternal: true },
        { id: "calculator", name: "Calculator", icon: "qrc:/images/calculator.svg", exec: "", isInternal: true },
        { id: "notes", name: "Notes", icon: "qrc:/images/notes.svg", exec: "", isInternal: true },
        { id: "settings", name: "Settings", icon: "qrc:/images/settings.svg", exec: "", isInternal: true }
    ]
    
    // Helper function to get app metadata by ID
    function getApp(appId) {
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].id === appId) {
                return apps[i]
            }
        }
        return null
    }
    
    // Get app name by ID
    function getAppName(appId) {
        var app = getApp(appId)
        return app ? app.name : appId
    }
    
    // Get app icon by ID
    function getAppIcon(appId) {
        var app = getApp(appId)
        return app ? app.icon : ""
    }
    
    // Check if app is internal (template app) or external (native app)
    function isInternalApp(appId) {
        var app = getApp(appId)
        return app ? app.isInternal : true
    }
}

