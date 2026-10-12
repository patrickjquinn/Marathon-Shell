import QtQuick

// Stands in for WebLayer.qml: records calls, and draws a fake page for renders.
Rectangle {
    id: root

    property var browser
    property int backs: 0
    property int forwards: 0
    property int reloads: 0
    property int captures: 0
    property var discarded: []
    property bool clearResult: true
    property int clears: 0

    signal scrolled(real y)

    function goBack() {
        backs++;
    }
    function goForward() {
        forwards++;
    }
    function reloadOrStop() {
        reloads++;
    }
    function discard(index) {
        discarded = discarded.concat([index]);
    }
    function capture() {
        captures++;
    }
    function clearSiteData() {
        clears++;
        return clearResult;
    }

    color: "#f2f2f2"

    Column {
        x: 40
        y: 60
        width: parent.width - 80
        spacing: 24

        Rectangle {
            width: parent.width * 0.6
            height: 48
            radius: 6
            color: "#3a6ea5"
        }
        Repeater {
            model: 9

            Rectangle {
                required property int index

                width: parent.width * (index % 3 === 2 ? 0.7 : 1)
                height: 22
                radius: 4
                color: "#c8c8c8"
            }
        }
        Rectangle {
            width: parent.width
            height: 360
            radius: 8
            color: "#d9e4ef"
        }
    }
}
