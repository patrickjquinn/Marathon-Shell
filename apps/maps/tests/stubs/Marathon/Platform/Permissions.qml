pragma Singleton
import QtQml

QtObject {
    property bool granted: true
    property var requests: []

    signal permissionGranted(string appId, string permission)
    signal permissionDenied(string appId, string permission)

    function hasPermission(appId, permission) {
        return granted;
    }

    function requestPermission(appId, permission) {
        requests = requests.concat([permission]);
    }

    function reset() {
        granted = true;
        requests = [];
    }
}
