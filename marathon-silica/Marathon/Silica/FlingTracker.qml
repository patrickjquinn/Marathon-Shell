import QtQuick
import Sailfish.Silica as S
import "Fling.js" as Fling
import "Velocity.js" as Velocity

// The fling a release starts, after Pacific's engine: the speed the content
// moved over the last 50 ms; none if the finger rested 40 ms before lifting;
// and a fling caught and flung again the same way adds the speed it was
// caught at, so a train of flings keeps getting faster.
QtObject {
    id: tracker

    required property Flickable view
    property var _motion: []
    property real _lastMove: 0
    property bool _dragged: false
    property real _flingVx: 0
    property real _flingVy: 0
    property real _flingAt: 0
    property real _caughtVx: 0
    property real _caughtVy: 0

    function _sample() {
        if (view.dragging) {
            Velocity.add(_motion, view.contentX, view.contentY);
            _lastMove = Date.now();
        } else if (view.flicking) {
            // In flick()'s sense: against the content's motion.
            _flingVx = -view.horizontalVelocity;
            _flingVy = -view.verticalVelocity;
            _flingAt = Date.now();
        }
    }

    function _carried(v, p) {
        return Math.sign(v) === Math.sign(p) && Math.abs(p) >= Fling.carryFloor * S.Theme.pixelRatio && Math.abs(v) >= Fling.carryMin * Math.abs(p) ? v + p : v;
    }

    property Connections _connections: Connections {
        target: tracker.view

        function onContentXChanged() {
            tracker._sample();
        }

        function onContentYChanged() {
            tracker._sample();
        }

        function onDraggingChanged() {
            if (!tracker.view.dragging)
                return;
            const caught = Date.now() - tracker._flingAt <= Fling.carryPauseMs;
            tracker._caughtVx = caught ? tracker._flingVx : 0;
            tracker._caughtVy = caught ? tracker._flingVy : 0;
            tracker._motion = [];
            tracker._dragged = true;
        }

        function onMovementEnded() {
            tracker._dragged = false;
        }

        function onFlickStarted() {
            if (!tracker._dragged)
                return;
            tracker._dragged = false;
            if (Date.now() - tracker._lastMove > Fling.pauseMs) {
                tracker.view.cancelFlick();
                return;
            }
            // Content coordinates: a fling moves contentY the other way.
            const fx = -Velocity.rate(tracker._motion, 1);
            const fy = -Velocity.rate(tracker._motion, 2);
            const vx = tracker._carried(fx, tracker._caughtVx);
            const vy = tracker._carried(fy, tracker._caughtVy);
            if (vx === 0 && vy === 0)
                return;
            const single = tracker.view.maximumFlickVelocity;
            if (vx !== fx || vy !== fy)
                tracker.view.maximumFlickVelocity = Fling.carryMaxVelocity * S.Theme.pixelRatio;
            tracker.view.flick(vx, vy);
            tracker.view.maximumFlickVelocity = single;
        }
    }
}
