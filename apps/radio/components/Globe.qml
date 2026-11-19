pragma ComponentBehavior: Bound
import QtQuick
import Marathon.Platform 1.0

// A dark dot-matrix globe of the places with stations. Drag turns it with
// the finger, a little slower while a place passes under the ring, so a
// place is easy to stop on; it never moves on its own while held. Let go,
// and a place near the ring settles into it; a fling lands on the place
// nearest where it would come to rest. Pinch (or the wheel) zooms. Tapping
// a place brings it to the centre. Either way `selected` says which.
Item {
    id: globe

    // [latitude, longitude, name, stations] per place.
    property var places: []
    // The point facing the viewer, degrees.
    property real lat: 25
    property real lon: 0
    property real zoom: 1
    readonly property real radius: zoom * Math.min(width, height) * 0.44
    // The place snapped to the centre, or -1.
    property int selected: -1
    // How far from the centre, in pixels, a place snaps in: the ring's radius.
    property real reach: 24
    // How near the ring, in pixels, a place must be to settle into it on
    // release; with none that near the globe stays where it was left.
    readonly property real capture: reach * 1.5
    // The height at the bottom where the globe takes no drags or taps.
    property real inputInset: 0
    readonly property bool moving: drag.active || pinch.active || coast.running || snap.running

    signal settled

    readonly property real _degPerPx: 180 / (Math.PI * radius)
    // Lattice spacing: finer as the globe grows, so dots stay about the
    // same size on screen and a country keeps its shape. The land mask and
    // the place map resolve the finest (0.18 degrees: 1.5 texels).
    readonly property real _step: zoom < 1.6 ? 1.0 : zoom < 2.6 ? 0.7 : zoom < 4 ? 0.5 : zoom < 6 ? 0.35 : zoom < 10 ? 0.25 : 0.18
    property real _vlat: 0
    property real _vlon: 0
    // The place last ticked under the ring while dragging, and when.
    property int _ticked: -1
    property real _tickedAt: 0
    // The coast's decay rate, per second: a fling's rest is velocity / it away.
    readonly property real _decay: 3.5
    property real _zoomFrom: 1

    function _wrap(lon) {
        return ((lon + 540) % 360) - 180;
    }

    function _distance(lat1, lon1, lat2, lon2) {
        const r = Math.PI / 180;
        const a = Math.sin((lat2 - lat1) * r / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin((lon2 - lon1) * r / 2) ** 2;
        return 2 * Math.asin(Math.min(1, Math.sqrt(a))) / r;
    }

    // The place nearest a point within `within` degrees of it, or -1.
    function _closest(atLat, atLon, within) {
        let best = -1;
        let bestD = within;
        for (let i = 0; i < places.length; i++) {
            const p = places[i];
            if (Math.abs(p[0] - atLat) > bestD)
                continue;
            const d = _distance(atLat, atLon, p[0], p[1]);
            if (d < bestD) {
                bestD = d;
                best = i;
            }
        }
        return best;
    }

    // The place inside the ring, or -1.
    function nearest() {
        return _closest(lat, lon, reach * _degPerPx);
    }

    // How much of the finger's travel turns the globe: less over a place
    // under the ring, a detent felt as resistance, never a jump. A light
    // tick as a place reaches the middle of the ring.
    function _gain() {
        const near = reach * 0.75;
        const i = _closest(lat, lon, near * _degPerPx);
        if (i < 0) {
            _ticked = -1;
            return 1;
        }
        const px = _distance(lat, lon, places[i][0], places[i][1]) / _degPerPx;
        // One tick per place, and no closer than 120 ms: a sweep across a
        // dense cluster is a blur, not a buzz.
        if (px < reach / 3 && i !== _ticked) {
            _ticked = i;
            const now = Date.now();
            if (now - _tickedAt >= 120) {
                _tickedAt = now;
                Haptics.light();
            }
        }
        const u = px / near;
        return 0.3 + 0.7 * u * u * (3 - 2 * u);
    }

    // A fling's landing: the place nearest where it would come to rest, met
    // at the release speed (an ease-out's start speed is 3 x distance / time).
    function _land() {
        const toLat = Math.max(-80, Math.min(80, lat + _vlat / _decay));
        const toLon = lon + _vlon / _decay;
        const i = _closest(toLat, _wrap(toLon), capture * _degPerPx);
        if (i < 0)
            return false;
        const speed = Math.sqrt(_vlat * _vlat + _vlon * _vlon);
        const d = _distance(lat, lon, places[i][0], places[i][1]);
        flyTo(places[i][0], places[i][1], zoom, Math.max(180, Math.min(700, speed > 0 ? 3000 * d / speed : 420)));
        return true;
    }

    // The latitude and longitude under a point of the item, or null off
    // the globe: the shader's ray cast, run backwards.
    function _at(x, y) {
        const px = (x - width / 2) / radius;
        const py = (y - height / 2) / radius;
        const r2 = px * px + py * py;
        if (r2 >= 1)
            return null;
        const vx = px, vy = -py, vz = Math.sqrt(1 - r2);
        const la = lat * Math.PI / 180, lo = lon * Math.PI / 180;
        const ay = vy * Math.cos(la) + vz * Math.sin(la);
        const az = -vy * Math.sin(la) + vz * Math.cos(la);
        const wx = vx * Math.cos(lo) + az * Math.sin(lo);
        const wz = -vx * Math.sin(lo) + az * Math.cos(lo);
        return [Math.asin(Math.max(-1, Math.min(1, ay))) * 180 / Math.PI, Math.atan2(wx, wz) * 180 / Math.PI];
    }

    // Brings the place under a tap to the centre: the nearest within a
    // fingertip of it.
    function _pick(x, y) {
        const at = _at(x, y);
        if (!at)
            return;
        const i = _closest(at[0], at[1], 28 * _degPerPx);
        if (i >= 0)
            flyTo(places[i][0], places[i][1], zoom);
    }

    property real _flyDuration: 420

    // Turns (and zooms) to a point, in `ms` (420 by default).
    function flyTo(toLat, toLon, toZoom, ms) {
        coast.stop();
        snap.stop();
        _flyDuration = ms === undefined ? 420 : ms;
        snapLat.to = Math.max(-80, Math.min(80, toLat));
        snapLon.to = lon + _wrap(toLon - lon);
        snapZoom.to = toZoom === undefined ? zoom : toZoom;
        snap.start();
    }

    function _rest() {
        const i = _closest(lat, lon, capture * _degPerPx);
        if (i >= 0 && (Math.abs(places[i][0] - lat) > 0.01 || Math.abs(_wrap(places[i][1] - lon)) > 0.01)) {
            _flyDuration = 420;
            snapLat.to = places[i][0];
            snapLon.to = lon + _wrap(places[i][1] - lon);
            snapZoom.to = zoom;
            snap.start();
            return;
        }
        lon = _wrap(lon);
        selected = i;
        settled();
    }

    onPlacesChanged: placeMap.requestPaint()
    on_StepChanged: placeMap.requestPaint()

    Image {
        id: landMask

        source: Qt.resolvedUrl("../assets/land.png")
        visible: false
        smooth: true
    }

    // The places as an equirectangular map the shader reads at each
    // lattice dot's centre: a place lights the one dot nearest it (the
    // lattice is the shader's, worked out the same way here), brighter for
    // more stations. Two texels square, so rounding cannot miss it.
    Canvas {
        id: placeMap

        width: 3072
        height: 1536
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onPaint: {
            const ctx = getContext("2d");
            ctx.fillStyle = "black";
            ctx.fillRect(0, 0, width, height);
            const step = globe._step * Math.PI / 180;
            const dots = {};
            for (const p of globe.places) {
                const lat = p[0] * Math.PI / 180;
                const lon = p[1] * Math.PI / 180;
                const latc = Math.floor(lat / step + 0.5) * step;
                const n = Math.max(1, Math.floor(2 * Math.PI * Math.cos(latc) / step + 0.5));
                const ls = 2 * Math.PI / n;
                const lonc = Math.floor(lon / ls + 0.5) * ls;
                const key = Math.round((lonc / (2 * Math.PI) + 0.5) * width) + "," + Math.round((0.5 - latc / Math.PI) * height);
                dots[key] = Math.max(dots[key] || 0, p[3]);
            }
            for (const key in dots) {
                const xy = key.split(",");
                const v = Math.min(1, 0.5 + 0.35 * Math.log10(dots[key] + 1));
                ctx.fillStyle = Qt.rgba(v, v, v, 1);
                ctx.fillRect(Number(xy[0]) - 1, Number(xy[1]) - 1, 2, 2);
            }
            placeTexture.scheduleUpdate();
        }
    }

    ShaderEffectSource {
        id: placeTexture

        sourceItem: placeMap
        hideSource: true
        live: false
        smooth: false
        width: 1
        height: 1
    }

    ShaderEffect {
        anchors.fill: parent

        property size size: Qt.size(width, height)
        property real radius: globe.radius
        property real lon0: globe.lon * Math.PI / 180
        property real lat0: globe.lat * Math.PI / 180
        property real dotStep: globe._step * Math.PI / 180
        property color landColor: "#5a5f63"
        property color seaColor: "#15181a"
        property color bodyColor: "#060809"
        property color stationColor: "#1de9b6"
        property color rimColor: "#0e3a33"
        property variant land: landMask
        property variant places: placeTexture

        fragmentShader: Qt.resolvedUrl("../shaders/globe.frag.qsb")
    }

    // The handlers' area: what lies over the bottom of the globe (the
    // page's station strip) keeps its own drags.
    Item {
        id: input

        anchors.fill: parent
        anchors.bottomMargin: globe.inputInset

        DragHandler {
            id: drag

            property point last

            target: null
            maximumPointCount: 1
            onActiveChanged: {
                if (active) {
                    coast.stop();
                    snap.stop();
                    globe.selected = -1;
                    globe._ticked = -1;
                    last = centroid.position;
                    return;
                }
                globe._vlon = -centroid.velocity.x * globe._degPerPx;
                globe._vlat = centroid.velocity.y * globe._degPerPx;
                // Let go slowly and a place near the ring settles into it; a
                // fling lands on the place nearest its rest, or coasts.
                if (Math.abs(globe._vlon) + Math.abs(globe._vlat) < 3 / globe.zoom)
                    globe._rest();
                else if (!globe._land())
                    coast.start();
            }
            onCentroidChanged: {
                if (!active)
                    return;
                const p = centroid.position;
                const k = globe._degPerPx * globe._gain();
                globe.lon -= (p.x - last.x) * k;
                globe.lat = Math.max(-80, Math.min(80, globe.lat + (p.y - last.y) * k));
                last = p;
            }
        }

        PinchHandler {
            id: pinch

            target: null
            onActiveChanged: {
                if (active) {
                    coast.stop();
                    snap.stop();
                    globe._zoomFrom = globe.zoom;
                } else {
                    globe._rest();
                }
            }
            onActiveScaleChanged: globe.zoom = Math.max(0.9, Math.min(20, globe._zoomFrom * activeScale))
        }

        WheelHandler {
            onWheel: event => {
                globe.zoom = Math.max(0.9, Math.min(20, globe.zoom * Math.pow(1.0015, event.angleDelta.y)));
                restTimer.restart();
            }
        }

        TapHandler {
            onSingleTapped: eventPoint => globe._pick(eventPoint.position.x, eventPoint.position.y)
            onDoubleTapped: globe.flyTo(globe.lat, globe.lon, Math.min(20, globe.zoom * 2.2))
        }
    }

    Timer {
        id: restTimer

        interval: 250
        onTriggered: globe._rest()
    }

    // The coast after a flick: velocity decays to rest, then the snap.
    FrameAnimation {
        id: coast

        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            globe.lon += globe._vlon * dt;
            globe.lat = Math.max(-80, Math.min(80, globe.lat + globe._vlat * dt));
            const decay = Math.exp(-dt * 3.5);
            globe._vlon *= decay;
            globe._vlat *= decay;
            if (Math.abs(globe._vlon) + Math.abs(globe._vlat) < 1.5 / globe.zoom) {
                stop();
                globe._rest();
            }
        }
    }

    ParallelAnimation {
        id: snap

        NumberAnimation {
            id: snapLat

            target: globe
            property: "lat"
            duration: globe._flyDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: snapLon

            target: globe
            property: "lon"
            duration: globe._flyDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: snapZoom

            target: globe
            property: "zoom"
            duration: globe._flyDuration
            easing.type: Easing.OutCubic
        }
        onFinished: {
            globe.lon = globe._wrap(globe.lon);
            globe.selected = globe.nearest();
            globe.settled();
        }
    }
}
