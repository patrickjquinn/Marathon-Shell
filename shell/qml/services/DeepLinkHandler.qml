pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root
    
    property var appWindow: null
    
    function handleDeepLink(appId, route, params) {
        Logger.info("DeepLinkHandler", "Deep link requested: " + appId)
        
        var app = AppStore.getApp(appId)
        if (app) {
            UIStore.openApp(app.id, app.name, app.icon)
            if (root.appWindow) {
                root.appWindow.show(app.id, app.name, app.icon, app.type)
            }
            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.bringToForeground(app.id)
            }
        } else {
            Logger.warn("DeepLinkHandler", "App not found for deep link: " + appId)
        }
    }
}

