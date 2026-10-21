import QtQml

QtObject {
    property bool available: true
    property bool muted: false
    property var spoken: []

    function speak(text) {
        spoken = spoken.concat([text]);
    }

    function stop() {
    }
}
