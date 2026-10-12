pragma Singleton
import QtQml

QtObject {
    property var launched: []

    function reset() {
        launched = [];
    }
    function launchApp(appId) {
        launched = launched.concat([appId]);
        return true;
    }
}
