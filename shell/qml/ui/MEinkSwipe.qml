import QtQuick
import MarathonOS.Shell

// E-paper's swipe: nothing follows the finger, since every frame of a drag
// is a panel update. Past `distance` along the axis, or released faster
// than `speed`, it turns once, and the view cuts to its next state.
DragHandler {
    id: root

    // The view's extent along the axis; the swipe turns at a share of it.
    property real extent: 0
    readonly property real distance: extent * MMotion.swipeShare
    // px/s, for a short flick.
    readonly property real speed: 600
    property bool turned: false
    property real velocity: 0

    // +1 for a swipe toward the start (left or up): the next page.
    signal turn(int step)

    function measure() {
        velocity = xAxis.enabled ? centroid.velocity.x : centroid.velocity.y;
        const moved = xAxis.enabled ? centroid.position.x - centroid.pressPosition.x : centroid.position.y - centroid.pressPosition.y;
        if (!turned && Math.abs(moved) >= distance) {
            turned = true;
            turn(moved < 0 ? 1 : -1);
        }
    }

    target: null
    enabled: MMotion.instant
    // Nothing redraws during the swipe, so Qt may hand over the whole
    // movement in the one update that activates the handler: measured
    // there too, not only on later moves.
    onActiveChanged: {
        if (active) {
            turned = false;
            measure();
        } else if (!turned && Math.abs(velocity) > speed) {
            turned = true;
            turn(velocity < 0 ? 1 : -1);
        }
    }
    onCentroidChanged: {
        if (active)
            measure();
    }
}
