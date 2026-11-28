pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Shapes

// Every finger on the keyboard, each on its own: a key goes down as a finger
// lands and types when it lifts, or as the next finger lands (two thumbs
// overlap). A touch between keys is the nearest key's. One finger sliding
// across the letters swipes a word, along the space bar moves the cursor,
// and left off backspace picks whole words to delete.
MultiPointTouchArea {
    id: root

    // The layout shown, whose keys this drives.
    property Item layout
    property bool swipeEnabled: true
    property color trailColor: "white"
    // A letter key's width: what slides are measured in.
    readonly property real pitch: _pitch > 0 ? _pitch : 60
    property real _pitch: 0
    property var _keys: []
    property bool _keysDirty: true
    property var _tracks: ({})
    property var _trail: []
    property string _letters: ""

    // A letter goes down at (x, y), just before its key types it.
    signal letterTapped(real x, real y)
    // A swipe through the letters: "x,y;x,y;..."
    signal swiped(string points)
    signal cursorStep(int direction)
    // How many words a slide off backspace would delete; 0 for none.
    signal deletePreview(int words)
    signal deleteWords(int words)
    // The letter keys moved: "q x y;w x y;..." and a letter key's width.
    signal lettersMoved(string keys, real pitch)

    function invalidate() {
        _keysDirty = true;
    }

    function _collect(item, out) {
        for (var i = 0; i < item.children.length; ++i) {
            var child = item.children[i];
            if (!child.visible)
                continue;
            if (child.isKeyboardKey === true) {
                child.routed = true;
                var at = child.mapToItem(root, 0, 0);
                out.push({
                    "item": child,
                    "x": at.x,
                    "y": at.y,
                    "w": child.width,
                    "h": child.height
                });
            } else {
                _collect(child, out);
            }
        }
    }

    function _ensureKeys() {
        if (!_keysDirty || !layout)
            return;
        var keys = [];
        _collect(layout, keys);
        _keys = keys;
        _keysDirty = false;
        var letters = [];
        var widths = [];
        for (var i = 0; i < keys.length; ++i) {
            var k = keys[i];
            if (k.item.isLetter) {
                letters.push(k.item.text.toLowerCase() + " " + (k.x + k.w / 2).toFixed(1) + " " + (k.y + k.h / 2).toFixed(1));
                widths.push(k.w);
            }
        }
        widths.sort((a, b) => a - b);
        _pitch = widths.length > 0 ? widths[Math.floor(widths.length / 2)] : 0;
        var spec = letters.join(";");
        if (spec !== "" && spec !== _letters) {
            _letters = spec;
            lettersMoved(spec, _pitch);
        }
    }

    function _keyAt(x, y) {
        _ensureKeys();
        var nearest = null;
        var nearestDistance = 1e9;
        for (var i = 0; i < _keys.length; ++i) {
            var k = _keys[i];
            if (x >= k.x && x < k.x + k.w && y >= k.y && y < k.y + k.h)
                return k.item;
            var dx = Math.max(k.x - x, 0, x - k.x - k.w);
            var dy = Math.max(k.y - y, 0, y - k.y - k.h);
            var d = Math.hypot(dx, dy);
            if (d < nearestDistance) {
                nearestDistance = d;
                nearest = k.item;
            }
        }
        return nearestDistance <= pitch ? nearest : null;
    }

    function _count() {
        return Object.keys(_tracks).length;
    }

    // A key still down types now: the next finger has landed.
    function _rollOver(except) {
        for (var id in _tracks) {
            var t = _tracks[id];
            if (id === except || t.mode !== "tap" || !t.key || t.key.showingAlternates || t.key.autoRepeat)
                continue;
            if (t.key.isLetter)
                letterTapped(t.x0, t.y0);
            t.key.pointerReleased(true);
            t.mode = "done";
        }
    }

    function _press(point) {
        var id = String(point.pointId);
        // Keys come and go with the layout's data: find them afresh each touch.
        if (_count() === 0)
            invalidate();
        _rollOver(id);
        var key = _keyAt(point.x, point.y);
        if (key) {
            var local = key.mapFromItem(root, point.x, point.y);
            key.pointerPressed(local.x, local.y);
        }
        _tracks[id] = {
            "key": key,
            "x0": point.x,
            "y0": point.y,
            "mode": key ? "tap" : "done",
            "path": [],
            "anchor": point.x,
            "words": 0
        };
    }

    function _move(point) {
        var t = _tracks[String(point.pointId)];
        if (!t)
            return;
        var dx = point.x - t.x0;
        var dy = point.y - t.y0;
        if (t.mode === "tap") {
            var key = t.key;
            if (key.showingAlternates) {
                var local = key.mapFromItem(root, point.x, point.y);
                key.pointerMoved(local.x, local.y);
                return;
            }
            var alone = _count() === 1;
            if (alone && key.text === " " && Math.abs(dx) > 0.5 * pitch) {
                key.pointerCanceled();
                t.mode = "cursor";
                t.anchor = t.x0 + (dx > 0 ? 0.5 : -0.5) * pitch;
            } else if (alone && key.text === "backspace" && dx < -0.6 * pitch) {
                key.pointerCanceled();
                t.mode = "delete";
            } else if (alone && swipeEnabled && key.isLetter && Math.hypot(dx, dy) > 0.6 * pitch && _keyAt(point.x, point.y) !== key) {
                key.pointerCanceled();
                t.mode = "swipe";
                t.path = [Qt.point(t.x0, t.y0)];
            } else if (!key.longPressTriggered) {
                var here = key.mapFromItem(root, point.x, point.y);
                key.pointerMoved(here.x, here.y);
                // Sliding onto another key moves the press there.
                var under = _keyAt(point.x, point.y);
                if (under && under !== key && !swipeEnabled) {
                    key.pointerCanceled();
                    under.pointerPressed();
                    t.key = under;
                }
            }
        }
        if (t.mode === "cursor") {
            var step = 0.4 * pitch;
            while (Math.abs(point.x - t.anchor) >= step) {
                var direction = point.x > t.anchor ? 1 : -1;
                t.anchor += direction * step;
                cursorStep(direction);
            }
        } else if (t.mode === "delete") {
            var words = dx > -0.4 * pitch ? 0 : 1 + Math.floor(Math.max(0, -dx - 0.6 * pitch) / (0.9 * pitch));
            if (words !== t.words) {
                t.words = words;
                if (SettingsManagerCpp.keyboardHapticStrength !== "off")
                    HapticManager.light();
                deletePreview(words);
            }
        } else if (t.mode === "swipe") {
            var last = t.path[t.path.length - 1];
            if (Math.hypot(point.x - last.x, point.y - last.y) >= 3) {
                t.path.push(Qt.point(point.x, point.y));
                _trail = t.path.slice();
                trailFade.stop();
                trail.opacity = 1;
            }
        }
    }

    function _release(point) {
        var id = String(point.pointId);
        var t = _tracks[id];
        if (!t)
            return;
        delete _tracks[id];
        if (t.mode === "tap") {
            if (t.key.isLetter && !t.key.showingAlternates)
                letterTapped(t.x0, t.y0);
            t.key.pointerReleased(true);
        } else if (t.mode === "swipe") {
            t.path.push(Qt.point(point.x, point.y));
            trailFade.restart();
            swiped(t.path.map(p => p.x.toFixed(1) + "," + p.y.toFixed(1)).join(";"));
        } else if (t.mode === "delete") {
            deletePreview(0);
            if (t.words > 0)
                deleteWords(t.words);
        }
    }

    function _cancelAll() {
        for (var id in _tracks) {
            var t = _tracks[id];
            if (t.mode === "tap")
                t.key.pointerCanceled();
            if (t.mode === "delete")
                deletePreview(0);
        }
        _tracks = {};
        _trail = [];
    }

    mouseEnabled: true
    maximumTouchPoints: 5
    onLayoutChanged: invalidate()
    onWidthChanged: invalidate()
    onHeightChanged: invalidate()
    onEnabledChanged: if (!enabled)
        _cancelAll()
    onPressed: function (points) {
        for (var i = 0; i < points.length; ++i)
            _press(points[i]);
    }
    onUpdated: function (points) {
        for (var i = 0; i < points.length; ++i)
            _move(points[i]);
    }
    onReleased: function (points) {
        for (var i = 0; i < points.length; ++i)
            _release(points[i]);
    }
    onCanceled: _cancelAll()

    Shape {
        id: trail

        anchors.fill: parent
        visible: root._trail.length > 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.trailColor
            strokeWidth: Math.max(4, root.pitch * 0.09)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root._trail
            }
        }

        NumberAnimation on opacity {
            id: trailFade

            running: false
            to: 0
            duration: MMotion.ms(180)
            onFinished: root._trail = []
        }
    }
}
