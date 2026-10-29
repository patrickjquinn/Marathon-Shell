pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    function simulateIncomingSMS(sender, text) {
        log("simulateIncomingSMS", sender, text);
    }
}
