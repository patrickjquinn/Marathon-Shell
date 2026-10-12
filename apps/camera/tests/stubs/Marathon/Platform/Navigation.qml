pragma Singleton
import QtQml

QtObject {
    property var launches: []

    function reset() { launches = []; }
    function launchApp(appId) {
        launches = launches.concat([appId]);
        return true;
    }
}
