import QtQuick

// Stands in for MapView, which needs WebEngine.
Rectangle {
    property var calls: []
    property int reloads: 0

    signal ready
    signal clicked(real latitude, real longitude)
    signal failed(string message)
    signal lost
    signal notice(string text)

    function run(js) {
        calls = calls.concat([js]);
    }

    function reload() {
        reloads++;
    }

    color: "#203830"
}
