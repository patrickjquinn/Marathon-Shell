import QtQuick

QtObject {
    id: root

    property var now: () => Date.now()
    readonly property bool running: endsAt >= 0
    property int total: 0
    property int remaining: 0
    property real endsAt: -1

    signal finished
    signal edited

    property Timer _tick: Timer {
        interval: 250
        repeat: true
        running: root.running
        onTriggered: root.update()
    }

    function update() {
        if (!running)
            return;
        remaining = Math.max(0, Math.ceil((endsAt - now.call()) / 1000));
        if (remaining === 0) {
            endsAt = -1;
            edited();
            finished();
        }
    }

    function set(seconds) {
        if (running)
            return;
        total = seconds;
        remaining = seconds;
        edited();
    }

    function start() {
        if (running || remaining <= 0)
            return;
        endsAt = now.call() + remaining * 1000;
        edited();
    }

    function pause() {
        update();
        endsAt = -1;
        edited();
    }

    function reset() {
        endsAt = -1;
        total = 0;
        remaining = 0;
        edited();
    }

    function snapshot() {
        return { endsAt: endsAt, total: total, remaining: remaining };
    }

    // Returns when the timer ended if that was while the app was closed, else -1.
    function restore(s) {
        total = s.total || 0;
        remaining = s.remaining || 0;
        const end = typeof s.endsAt === "number" ? s.endsAt : -1;
        if (end >= 0 && end <= now.call()) {
            remaining = 0;
            edited();
            return end;
        }
        endsAt = end;
        update();
        return -1;
    }
}
