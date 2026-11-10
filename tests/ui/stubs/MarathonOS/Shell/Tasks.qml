pragma Singleton
import QtQml

QtObject {
    property bool androidStarting: false
    property var secureApps: []
    signal appUnregistered(string appId)
    signal appCommand(string appId, string command)
    signal coverActionStripChanged(string appId)
    function setCoverVisible(appId, visible) {
    }
    function coverActionStrip(appId) {
        return 0;
    }
    function closeAppWindows(appId) {
        return 0;
    }
    function launchAppWithRoute() {
    }
    function closeApp(appId, skipNativeClose) {
    }
    function registerApp(appId, info) {
    }
    function unregisterApp(appId) {
    }
}
