pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root

    property var appWindow: null

    function handleDeepLink(appId, route, params) {
        Logger.info("DeepLinkHandler", "Deep link requested: " + appId);

        // Use MarathonAppRegistry instead of AppStore
        var appInfo = typeof MarathonAppRegistry !== 'undefined' ? MarathonAppRegistry.getApp(appId) : null;

        if (appInfo && appInfo.id) {
            UIStore.openApp(appInfo.id, appInfo.name, appInfo.icon);
            if (root.appWindow) {
                root.appWindow.show(appInfo.id, appInfo.name, appInfo.icon, appInfo.type);
            }
            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.bringToForeground(appInfo.id);
            }
        } else {
            Logger.warn("DeepLinkHandler", "App not found for deep link: " + appId);
        }
    }
}
