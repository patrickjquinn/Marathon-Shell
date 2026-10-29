pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    function addContact(name, phone, email) {
        log("addContact", name, phone, email);
    }
}
