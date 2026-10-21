pragma Singleton
import QtQml
QtObject {
    property bool androidStarting: false
    property var secureApps: []
    signal appUnregistered(string appId)
    signal appCommand(string appId, string command)
    function setCoverVisible(appId, visible) {}
    function closeAppWindows(appId) { return 0; }
    function launchAppWithRoute() {}
    function closeApp(appId, skipNativeClose) {}
    function registerApp(appId, info) {}
    function unregisterApp(appId) {}
}
