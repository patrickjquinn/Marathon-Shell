import QtQuick

QtObject {
    id: root

    property var now: () => Date.now()
    // Gates the display tick only; elapsed time is wall-clock based.
    property bool ticking: true
    readonly property bool running: startedAt >= 0
    property real elapsed: 0
    property var laps: []
    property real startedAt: -1
    property real before: 0

    property Timer _tick: Timer {
        interval: 16
        repeat: true
        running: root.running && root.ticking
        onTriggered: root.update()
    }

    function update() {
        elapsed = running ? before + now() - startedAt : before;
    }

    function start() {
        if (running)
            return;
        startedAt = now();
        update();
    }

    function stop() {
        if (!running)
            return;
        before += now() - startedAt;
        startedAt = -1;
        update();
    }

    function lap() {
        update();
        laps = laps.concat([elapsed]);
    }

    function reset() {
        startedAt = -1;
        before = 0;
        laps = [];
        update();
    }
}
