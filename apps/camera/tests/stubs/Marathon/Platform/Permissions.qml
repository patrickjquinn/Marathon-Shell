pragma Singleton
import QtQml

QtObject {
    property var requests: []

    function reset() { requests = []; }
    function requestPermission(appId, permission) { requests = requests.concat([appId + ":" + permission]); }
}
