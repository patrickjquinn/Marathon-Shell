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

    signal edited

    property FrameAnimation _tick: FrameAnimation {
        running: root.running && root.ticking
        onTriggered: root.update()
    }

    function update() {
        elapsed = running ? before + now.call() - startedAt : before;
    }

    function start() {
        if (running)
            return;
        startedAt = now.call();
        update();
        edited();
    }

    function stop() {
        if (!running)
            return;
        before += now.call() - startedAt;
        startedAt = -1;
        update();
        edited();
    }

    function lap() {
        update();
        laps = laps.concat([elapsed]);
        edited();
    }

    function reset() {
        startedAt = -1;
        before = 0;
        laps = [];
        update();
        edited();
    }

    function snapshot() {
        return {
            startedAt: startedAt,
            before: before,
            laps: laps
        };
    }

    function restore(s) {
        startedAt = typeof s.startedAt === "number" ? s.startedAt : -1;
        before = s.before || 0;
        laps = Array.isArray(s.laps) ? s.laps : [];
        update();
    }
}
