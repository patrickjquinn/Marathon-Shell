import QtQuick
import MarathonOS.Shell

// E-paper's swipe: nothing follows the finger, since every frame of a drag
// is a panel update. Past `distance` along the axis, or released faster
// than `speed`, it turns once, and the view cuts to its next state.
MAxisDrag {
    id: root

    // The view's extent along the axis; the swipe turns at a share of it.
    property real extent: 0
    readonly property real distance: extent * MMotion.swipeShare
    // px/s, for a short flick.
    readonly property real threshold: 600
    property bool turned: false
    property real velocity: 0

    // +1 for a swipe toward the start (left or up): the next page.
    signal turn(int step)

    function measure() {
        velocity = speed();
        const moved = travel();
        if (!turned && Math.abs(moved) >= distance) {
            turned = true;
            console.debug(log, "turn", moved < 0 ? 1 : -1, "at", moved, "of", distance);
            turn(moved < 0 ? 1 : -1);
        }
    }

    enabled: MMotion.instant
    // The update that activates the handler can carry the whole movement:
    // measured there too, not only on later moves.
    onActiveChanged: {
        if (active) {
            turned = false;
            measure();
        } else if (!turned && Math.abs(velocity) > threshold) {
            turned = true;
            console.debug(log, "turn", velocity < 0 ? 1 : -1, "at", velocity, "px/s");
            turn(velocity < 0 ? 1 : -1);
        }
    }
    onCentroidChanged: {
        if (active)
            measure();
    }
}
