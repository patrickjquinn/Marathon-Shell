pragma Singleton
import QtQml

QtObject {
    property bool available: true
    property var played: []

    function reset() {
        available = true;
        played = [];
    }
    function light() {
        played = played.concat(["light"]);
    }
    function medium() {
        played = played.concat(["medium"]);
    }
    function heavy() {
        played = played.concat(["heavy"]);
    }
}
