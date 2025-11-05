pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root
    
    property var compositor: null
    property var pendingNativeApp: null
    
    function launchApp(app, compositorRef, appWindowRef) {
        Logger.info("AppLaunchService", "Launching app: " + app.name + " (type: " + app.type + ")")
        
        if (!appWindowRef) {
            Logger.error("AppLaunchService", "appWindow reference not provided")
            return
        }
        
        if (app.type === "native") {
            if (!compositorRef) {
                Logger.warn("AppLaunchService", "Cannot launch native app - compositor not available")
                return
            }
            
            root.pendingNativeApp = app
            root.compositor = compositorRef
            
            UIStore.openApp(app.id, app.name, app.icon)
            appWindowRef.show(app.id, app.name, app.icon, "native", null, -1)
            Logger.info("AppLaunchService", "Showing splash screen for native app: " + app.name)
            
            compositorRef.launchApp(app.exec)
        } else {
            UIStore.openApp(app.id, app.name, app.icon)
            appWindowRef.show(app.id, app.name, app.icon, app.type)
            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.bringToForeground(app.id)
            }
        }
    }
    
    function launchFromSearch(result, compositorRef, appWindowRef) {
        Logger.info("AppLaunchService", "Launching from search: " + result.name + " (type: " + result.type + ")")
        
        if (result.type === "native") {
            if (compositorRef) {
                root.pendingNativeApp = result
                root.compositor = compositorRef
                
                UIStore.openApp(result.id, result.name, result.icon)
                appWindowRef.show(result.id, result.name, result.icon, "native", null, -1)
                Logger.info("AppLaunchService", "Showing splash screen for native app from search: " + result.name)
                
                compositorRef.launchApp(result.exec)
                Logger.info("AppLaunchService", "Launched native app from search: " + result.name)
            }
        } else {
            if (typeof AppLifecycleManager !== 'undefined' && AppLifecycleManager.isAppRunning(result.id)) {
                AppLifecycleManager.bringToForeground(result.id)
                Logger.info("AppLaunchService", "Brought running app to foreground: " + result.name)
            } else {
                UIStore.openApp(result.id, result.name, result.icon)
                appWindowRef.show(result.id, result.name, result.icon, "marathon")
                Logger.info("AppLaunchService", "Launched Marathon app from search: " + result.name)
            }
        }
    }
}

