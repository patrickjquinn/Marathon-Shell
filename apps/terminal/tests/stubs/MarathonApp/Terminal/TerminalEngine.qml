import QtQuick

// Records what the QML sends instead of running a shell.
QtObject {
    property bool running: false
    property string title: "Terminal"
    property int starts: 0
    property var sent: []
    property var lines: []
    property var size: [0, 0]

    signal finished(int exitCode)

    function start() {
        starts++;
        running = true;
    }
    function terminate() {
        running = false;
    }
    function sendInput(text) {
        sent = sent.concat([{ input: text }]);
    }
    function sendKey(key, text, modifiers) {
        sent = sent.concat([{ key: key, text: text, modifiers: modifiers }]);
    }
    function resize(cols, rows) {
        size = [cols, rows];
    }
    function recentLines(count) {
        return lines.slice(Math.max(0, lines.length - count));
    }
}
