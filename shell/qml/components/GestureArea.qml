import MarathonUI.Theme
import QtQuick

MouseArea {
    id: gestureArea

    property real startY: 0
    property bool isPeeking: false

    signal peekStarted
    signal peekProgress(real progress)
    signal peekReleased(bool committed)

    preventStealing: false
    propagateComposedEvents: true
    onPressed: mouse => {
        startY = mouse.y;
        if (mouse.y > height - Constants.peekThreshold) {
            isPeeking = true;
            peekStarted();
            mouse.accepted = true;
        } else {
            mouse.accepted = false;
        }
    }
    onPositionChanged: mouse => {
        if (isPeeking) {
            var dragY = startY - mouse.y;
            var progress = Math.max(0, Math.min(1, dragY / Constants.commitThreshold));
            peekProgress(progress);
            mouse.accepted = true;
        }
    }
    onReleased: mouse => {
        if (isPeeking) {
            var dragY = startY - mouse.y;
            var committed = dragY > Constants.commitThreshold;
            peekReleased(committed);
            isPeeking = false;
            mouse.accepted = true;
        }
    }
}
