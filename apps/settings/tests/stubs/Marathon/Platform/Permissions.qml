pragma Singleton
import QtQml

QtObject {
    property var granted: ({})
    property bool fail: false
    property var calls: []

    signal permissionGranted(string appId, string permission)
    signal permissionDenied(string appId, string permission)

    function reset() {
        granted = { "weather/network": true };
        fail = false;
        calls = [];
    }
    function hasPermission(appId, permission) {
        return !!granted[appId + "/" + permission];
    }
    function setPermission(appId, permission, value) {
        calls = calls.concat([[appId, permission, value]]);
        if (fail)
            return false;
        const next = Object.assign({}, granted);
        next[appId + "/" + permission] = value;
        granted = next;
        return true;
    }
}
