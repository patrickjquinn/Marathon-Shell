pragma ComponentBehavior: Bound
import QtQuick

// A dark dot-matrix globe of the places with stations. Drag turns it under
// the finger and it coasts on release; pinch (or the wheel) zooms. When it
// comes to rest near a place it snaps that place to the centre, like a
// dial finding a station, and says so with `selected`.
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
    readonly property bool moving: drag.active || pinch.active || coast.running || snap.running

    signal settled

    readonly property real _degPerPx: 180 / (Math.PI * radius)
    // Lattice spacing: finer as the globe grows, so dots stay dots.
    readonly property real _step: zoom < 2.2 ? 1.2 : 0.6
    property real _vlat: 0
    property real _vlon: 0
    property real _zoomFrom: 1

    function _wrap(lon) {
        return ((lon + 540) % 360) - 180;
    }

    function _distance(lat1, lon1, lat2, lon2) {
        const r = Math.PI / 180;
        const a = Math.sin((lat2 - lat1) * r / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin((lon2 - lon1) * r / 2) ** 2;
        return 2 * Math.asin(Math.min(1, Math.sqrt(a))) / r;
    }

    // The place nearest the centre within reach of a snap, or -1.
    function nearest() {
        const reach = Math.max(1.5, 7 / zoom);
        let best = -1;
        let bestD = reach;
        for (let i = 0; i < places.length; i++) {
            const p = places[i];
            if (Math.abs(p[0] - lat) > bestD)
                continue;
            const d = _distance(lat, lon, p[0], p[1]);
            if (d < bestD) {
                bestD = d;
                best = i;
            }
        }
        return best;
    }

    // Turns (and zooms) to a point.
    function flyTo(toLat, toLon, toZoom) {
        coast.stop();
        snap.stop();
        snapLat.to = Math.max(-80, Math.min(80, toLat));
        snapLon.to = lon + _wrap(toLon - lon);
        snapZoom.to = toZoom === undefined ? zoom : toZoom;
        snap.start();
    }

    function _rest() {
        const i = nearest();
        if (i >= 0 && (Math.abs(places[i][0] - lat) > 0.01 || Math.abs(_wrap(places[i][1] - lon)) > 0.01)) {
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

        width: 2048
        height: 1024
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
                last = centroid.position;
                return;
            }
            globe._vlon = -centroid.velocity.x * globe._degPerPx;
            globe._vlat = centroid.velocity.y * globe._degPerPx;
            coast.start();
        }
        onCentroidChanged: {
            if (!active)
                return;
            const p = centroid.position;
            globe.lon -= (p.x - last.x) * globe._degPerPx;
            globe.lat = Math.max(-80, Math.min(80, globe.lat + (p.y - last.y) * globe._degPerPx));
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
        onActiveScaleChanged: globe.zoom = Math.max(0.9, Math.min(12, globe._zoomFrom * activeScale))
    }

    WheelHandler {
        onWheel: event => {
            globe.zoom = Math.max(0.9, Math.min(12, globe.zoom * Math.pow(1.0015, event.angleDelta.y)));
            restTimer.restart();
        }
    }

    TapHandler {
        onDoubleTapped: globe.flyTo(globe.lat, globe.lon, Math.min(12, globe.zoom * 2.2))
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
            duration: 420
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: snapLon

            target: globe
            property: "lon"
            duration: 420
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: snapZoom

            target: globe
            property: "zoom"
            duration: 420
            easing.type: Easing.OutCubic
        }
        onFinished: {
            globe.lon = globe._wrap(globe.lon);
            const i = globe.nearest();
            globe.selected = i;
            globe.settled();
        }
    }
}
