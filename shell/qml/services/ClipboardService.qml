pragma Singleton
import QtQuick
import Qt.labs.settings 1.0

QtObject {
    id: clipboardService

    property var clipboardHistory: []
    readonly property int maxHistorySize: 20

    property var settings: Settings {
        category: "Clipboard"
        property alias history: clipboardService.clipboardHistory
    }

    signal clipboardChanged(var item)
    signal historyCleared

    function addToHistory(text, type) {
        if (!text || text.length === 0)
            return;
        var item = {
            text: text,
            type: type || "text",
            timestamp: Date.now()
        };

        for (var i = 0; i < clipboardHistory.length; i++) {
            if (clipboardHistory[i].text === text) {
                clipboardHistory.splice(i, 1);
                break;
            }
        }

        clipboardHistory.unshift(item);

        if (clipboardHistory.length > maxHistorySize) {
            clipboardHistory = clipboardHistory.slice(0, maxHistorySize);
        }

        clipboardHistory = clipboardHistory;
        clipboardChanged(item);

        console.log("[ClipboardService] Added to history, total items:", clipboardHistory.length);
    }

    function copyToClipboard(text) {
        console.log("[ClipboardService] Copy to clipboard:", text);
        addToHistory(text, "text");
    }

    function getHistory() {
        return clipboardHistory;
    }

    function deleteItem(index) {
        if (index >= 0 && index < clipboardHistory.length) {
            clipboardHistory.splice(index, 1);
            clipboardHistory = clipboardHistory;
            console.log("[ClipboardService] Deleted item at index:", index);
        }
    }

    function clearHistory() {
        clipboardHistory = [];
        historyCleared();
        console.log("[ClipboardService] History cleared");
    }

    Component.onCompleted: {
        console.log("[ClipboardService] Initialized with", clipboardHistory.length, "items");
    }
}
