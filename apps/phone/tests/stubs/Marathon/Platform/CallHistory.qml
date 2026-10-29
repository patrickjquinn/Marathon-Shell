pragma Singleton
import QtQml

QtObject {
    property var history: []
    property var deleted: []

    function reset() {
        history = [];
        deleted = [];
    }
    function deleteCall(id) {
        deleted = deleted.concat([id]);
        history = history.filter(c => c.id !== id);
    }
    function clearHistory() {
        history = [];
    }
}
