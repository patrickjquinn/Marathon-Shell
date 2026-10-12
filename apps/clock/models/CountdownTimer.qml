import QtQuick

QtObject {
    id: root

    property var now: () => Date.now()
    readonly property bool running: endsAt >= 0
    property int total: 0
    property int remaining: 0
    property real endsAt: -1

    signal finished

    property Timer _tick: Timer {
        interval: 250
        repeat: true
        running: root.running
        onTriggered: root.update()
    }

    function update() {
        if (!running)
            return;
        remaining = Math.max(0, Math.ceil((endsAt - now()) / 1000));
        if (remaining === 0) {
            endsAt = -1;
            finished();
        }
    }

    function set(seconds) {
        if (running)
            return;
        total = seconds;
        remaining = seconds;
    }

    function start() {
        if (running || remaining <= 0)
            return;
        endsAt = now() + remaining * 1000;
    }

    function pause() {
        update();
        endsAt = -1;
    }

    function reset() {
        endsAt = -1;
        total = 0;
        remaining = 0;
    }
}
