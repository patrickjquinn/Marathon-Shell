import QtQuick
import "Fling.js" as Fling

// Over a moving view, a press only stops it: nothing under it is pressed,
// highlighted or clicked, as on Android. Also for a moment after a fling
// ends, since the finger came down while the content still moved.
MouseArea {
    id: stopper

    required property Flickable view
    property bool _flung: false

    x: 0
    y: 0
    z: 10000
    width: view.width
    height: view.height
    enabled: view.moving || guard.running

    Component.onCompleted: parent = view

    Timer {
        id: guard

        interval: Fling.flingTapGuard
    }

    Connections {
        target: stopper.view

        function onFlickingChanged() {
            if (stopper.view.flicking)
                stopper._flung = true;
        }

        function onMovementEnded() {
            if (stopper._flung)
                guard.restart();
            stopper._flung = false;
        }
    }
}
