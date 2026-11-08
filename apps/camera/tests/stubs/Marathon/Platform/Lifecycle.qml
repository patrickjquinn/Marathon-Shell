pragma Singleton
import QtQml

QtObject {
    property int tasks

    function beginBackgroundTask(kind, reason) {
        return ++tasks;
    }
    function endBackgroundTask(id) {
    }
}
