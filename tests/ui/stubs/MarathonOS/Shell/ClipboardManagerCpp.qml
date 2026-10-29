pragma Singleton
import QtQml

QtObject {
    property var history: [
        {
            "text": "hello",
            "timestamp": 0
        }
    ]
    property bool cleared: false
    function clearHistory() {
        cleared = true;
        history = [];
    }
    function copyToClipboard(text) {
    }
    function deleteItem(index) {
    }
}
