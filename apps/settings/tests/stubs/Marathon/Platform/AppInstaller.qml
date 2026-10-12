pragma Singleton
import QtQml

QtObject {
    property var uninstalled: []

    signal uninstallComplete(string appId)
    signal uninstallFailed(string appId, string error)

    function reset() {
        uninstalled = [];
    }
    function uninstallApp(appId) {
        uninstalled = uninstalled.concat([appId]);
        return true;
    }
}
