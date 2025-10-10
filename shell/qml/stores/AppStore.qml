pragma Singleton
import QtQuick

QtObject {
    id: appStore
    
    property var apps: [
        { id: "phone", name: "Phone", icon: "qrc:/images/phone.svg", exec: "" },
        { id: "messages", name: "Messages", icon: "qrc:/images/messages.svg", exec: "" },
        { id: "browser", name: "Browser", icon: "qrc:/images/browser.svg", exec: "" },
        { id: "camera", name: "Camera", icon: "qrc:/images/camera.svg", exec: "" },
        { id: "gallery", name: "Gallery", icon: "qrc:/images/gallery.svg", exec: "" },
        { id: "music", name: "Music", icon: "qrc:/images/music.svg", exec: "" },
        { id: "calendar", name: "Calendar", icon: "qrc:/images/calendar.svg", exec: "" },
        { id: "clock", name: "Clock", icon: "qrc:/images/clock.svg", exec: "" },
        { id: "maps", name: "Maps", icon: "qrc:/images/maps.svg", exec: "" },
        { id: "calculator", name: "Calculator", icon: "qrc:/images/calculator.svg", exec: "" },
        { id: "notes", name: "Notes", icon: "qrc:/images/notes.svg", exec: "" },
        { id: "settings", name: "Settings", icon: "qrc:/images/settings.svg", exec: "" }
    ]
    
    property var runningApps: []
    property string currentApp: ""
    
    signal appLaunched(string appId)
    signal appClosed(string appId)
    signal appSwitched(string appId)
    
    function launchApp(appId) {
        console.log("============ LAUNCHING APP:", appId, "============")
        
        var app = getApp(appId)
        if (!app) {
            console.error("App not found:", appId)
            return
        }
        
        var alreadyRunning = false
        for (var i = 0; i < runningApps.length; i++) {
            if (runningApps[i].id === appId) {
                alreadyRunning = true
                break
            }
        }
        
        if (!alreadyRunning) {
            runningApps.push({
                id: app.id,
                name: app.name,
                icon: app.icon,
                preview: app.icon,
                timestamp: Date.now()
            })
            runningAppsChanged()
            console.log("App added to running apps. Total running:", runningApps.length)
        } else {
            console.log("App already running, switching to it")
        }
        
        currentApp = appId
        appLaunched(appId)
    }
    
    function closeApp(appId) {
        console.log("============ CLOSING APP:", appId, "============")
        
        for (var i = 0; i < runningApps.length; i++) {
            if (runningApps[i].id === appId) {
                runningApps.splice(i, 1)
                runningAppsChanged()
                console.log("App removed from running apps. Total running:", runningApps.length)
                
                if (currentApp === appId) {
                    currentApp = ""
                }
                
                appClosed(appId)
                return
            }
        }
    }
    
    function switchToApp(appId) {
        console.log("Switching to app:", appId)
        currentApp = appId
        appSwitched(appId)
    }
    
    function getApp(appId) {
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].id === appId) {
                return apps[i]
            }
        }
        return null
    }
    
    function closeAllApps() {
        console.log("Closing all apps")
        runningApps = []
        currentApp = ""
    }
}

