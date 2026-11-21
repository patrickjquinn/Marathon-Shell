pragma Singleton
import QtQml

QtObject {
    property bool available: true
    property var asked: []
    property int sheetsShown: 0
    signal answered(string question, string text)
    function ask(question) {
        asked = asked.concat([question]);
    }
    function warm() {
    }
    function showSheetFor(pid) {
        sheetsShown++;
    }
}
