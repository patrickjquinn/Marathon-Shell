import QtQml

// Stand-in for the C++ GestureTracker: same API, last-two-sample velocity,
// and a settle that lands at once.
QtObject {
    id: root

    property real value: 0
    property real velocity: 0
    property real from: 0
    property real to: 1
    readonly property real progress: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))
    property real commitDistance: 0
    property real flingVelocity: 500
    property int settleDuration: 300
    property real dampingRatio: 1
    property bool active: false
    readonly property bool settling: false
    readonly property bool willCommit: commitDistance > 0 && (value - from) * (to >= from ? 1 : -1) >= commitDistance
    property real lastT: 0
    property real lastV: 0

    signal settled

    function decide(distance, v) {
        if (Math.abs(v) >= flingVelocity)
            return v > 0 && distance > 0;
        return distance + v * 0.1 >= commitDistance;
    }
    function press() {
        active = true;
        velocity = 0;
        lastT = Date.now();
        lastV = value;
    }
    function move(v) {
        if (!active)
            press();
        const t = Date.now();
        if (t > lastT)
            velocity = (v - lastV) / (t - lastT) * 1000;
        lastT = t;
        lastV = v;
        value = v;
    }
    function release() {
        active = false;
        const dir = to >= from ? 1 : -1;
        return decide((value - from) * dir, velocity * dir);
    }
    function settleTo(target) {
        active = false;
        value = target;
        velocity = 0;
        settled();
    }
    function stop() {
    }
}
