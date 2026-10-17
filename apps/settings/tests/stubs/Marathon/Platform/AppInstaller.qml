pragma Singleton
import QtQml

QtObject {
    property var uninstalled: []
    // The shell's answer: user installs only.
    property var removable: ["notes", "weather"]

    signal uninstallComplete(string appId)
    signal uninstallFailed(string appId, string error)

    function reset() {
        uninstalled = [];
        removable = ["notes", "weather"];
    }
    function canUninstall(appId) {
        return removable.indexOf(appId) >= 0;
    }
    function uninstallApp(appId) {
        uninstalled = uninstalled.concat([appId]);
    }
}
