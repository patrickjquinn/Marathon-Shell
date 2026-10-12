pragma ComponentBehavior: Bound
import QtQuick
import QtPositioning as QP
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Maps
import "MapsLogic.js" as Logic
import "pages"
import "cover"

ApplicationWindow {
    id: root

    // Swapped for a placeholder in tests, where WebEngine can't render.
    property url mapSource: Qt.resolvedUrl("MapView.qml")
    property Item map: null
    property bool mapReady: false
    property string mapError: ""
    readonly property bool mapUnavailable: mapError !== "" && Logic.mapFailureIsPermanent(mapError)
    property var _pending: []

    property var searchResults: []
    property bool searching: false
    property string searchError: ""
    property string lastQuery: ""
    property var fetch: function (url, done) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "MarathonOS/1.0");
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                done(xhr.status, xhr.responseText);
        };
        xhr.send();
    }

    property var selectedPlace: null
    // "idle", "preview" (route shown, not started) or "active" (navigating).
    property string routingMode: "idle"
    property var currentRoute: null
    property var routeStart: null
    property string currentMode: "auto"
    property int currentManeuverIndex: 0
    // Metres to the next maneuver from the last fix, or -1 before one.
    property real nextDistance: -1
    property bool _cued: false
    property var _coords: []
    property bool awaitingStartPoint: false
    property bool directionsPending: false

    readonly property var maneuvers: currentRoute ? currentRoute.maneuvers : []
    readonly property var nextManeuver: maneuvers.length === 0 ? null : maneuvers[Math.min(currentManeuverIndex + 1, maneuvers.length - 1)]
    readonly property real distanceToNext: nextDistance >= 0 ? nextDistance : maneuvers.length > 0 ? (maneuvers[currentManeuverIndex].length || 0) * 1000 : 0
    readonly property var remainingRoute: Logic.remaining(maneuvers, currentManeuverIndex, nextDistance)
    readonly property bool arrived: routingMode === "active" && currentManeuverIndex === maneuvers.length - 1

    property var location: typeof Location !== "undefined" ? Location : null
    property var permissions: typeof Permissions !== "undefined" ? Permissions : null
    property var lifecycle: typeof Lifecycle !== "undefined" ? Lifecycle : null
    property bool hasLocationPermission: permissions !== null && permissions.hasPermission(appId, "location")
    property var _pendingLocation: null
    property int _navTask: 0
    // How long a finished route stays up before navigation ends itself.
    property int arrivalLinger: 60000

    readonly property bool geoclueValid: location !== null && location.available === true && location.latitude !== 0 && location.longitude !== 0
    readonly property bool fixValid: geoclueValid || positionSource.position.coordinate.isValid
    readonly property var fix: geoclueValid ? { lat: location.latitude, lon: location.longitude } : positionSource.position.coordinate.isValid ? { lat: positionSource.position.coordinate.latitude, lon: positionSource.position.coordinate.longitude } : { lat: 37.7749, lon: -122.419 }

    property var router: ValhallaRoutingClient {
        onRouteReady: (geojson, maneuvers, durationSec, distanceM, summary) => root._routeReady(geojson, maneuvers, durationSec, distanceM, summary)
        onRouteFailed: () => Notices.show(qsTr("Couldn't find a route to this place. Check your internet connection and try again."))
    }
    // VoiceClient only exists when the build found Qt TextToSpeech.
    property var voice: null

    function mapCall(method) {
        const args = Array.prototype.slice.call(arguments, 1).map(a => JSON.stringify(a)).join(",");
        const js = "if(window.MarathonMaps&&window.MarathonMaps." + method + ")window.MarathonMaps." + method + "(" + args + ");";
        if (map && mapReady)
            map.run(js);
        else
            _pending.push(js);
    }

    function attachMap(item) {
        map = item;
        item.ready.connect(() => {
            mapReady = true;
            mapError = "";
            const queued = _pending;
            _pending = [];
            queued.forEach(js => map.run(js));
            if (fixValid)
                mapCall("setUserLocation", fix.lat, fix.lon);
            if (!selectedPlace)
                mapCall("setCenter", fix.lat, fix.lon, 14);
        });
        item.clicked.connect((lat, lon) => {
            if (awaitingStartPoint && selectedPlace) {
                awaitingStartPoint = false;
                routeFrom(lat, lon);
            }
        });
        item.failed.connect(message => {
            console.warn("Maps: MapLibre failed:", message);
            mapError = message;
        });
        item.lost.connect(() => mapReady = false);
        item.notice.connect(text => Notices.show(text));
    }

    function retryMap() {
        mapError = "";
        mapReady = false;
        map.reload();
    }

    function search(query) {
        lastQuery = query;
        searchError = "";
        if (query.length === 0) {
            searchResults = [];
            searching = false;
            return;
        }
        searching = true;
        fetch("https://nominatim.openstreetmap.org/search?q=" + encodeURIComponent(query) + "&format=json&limit=10", (status, text) => {
            if (query !== lastQuery)
                return;
            searching = false;
            const places = status === 200 ? Logic.parseResults(text) : null;
            searchResults = places || [];
            if (status === 0)
                searchError = qsTr("Couldn't reach the search service. Check your internet connection and try again.");
            else if (places === null)
                searchError = qsTr("The search service isn't responding right now. Try again in a moment.");
        });
    }

    function selectPlace(place) {
        selectedPlace = place;
        mapCall("clearPins");
        mapCall("addPin", "place", place.lat, place.lon, "destination");
        mapCall("setCenter", place.lat, place.lon, 15);
    }

    function clearPlace() {
        if (routingMode !== "idle")
            endNavigation();
        selectedPlace = null;
        mapCall("clearPins");
    }

    function requireLocation(callback) {
        if (permissions === null || permissions.hasPermission(appId, "location")) {
            callback();
            return;
        }
        _pendingLocation = callback;
        permissions.requestPermission(appId, "location");
    }

    function locateMe() {
        requireLocation(() => {
            if (fixValid) {
                mapCall("setCenter", fix.lat, fix.lon, 15);
                return;
            }
            Notices.show(qsTr("Finding your location. Make sure location is turned on, then try again."));
            if (location)
                location.start();
        });
    }

    function routeFrom(lat, lon) {
        routeStart = { lat: lat, lon: lon };
        router.requestRoute(lat, lon, selectedPlace.lat, selectedPlace.lon, currentMode);
    }

    function setMode(mode) {
        if (mode === currentMode)
            return;
        currentMode = mode;
        if (routeStart && selectedPlace)
            routeFrom(routeStart.lat, routeStart.lon);
    }

    function requestDirections() {
        if (!selectedPlace)
            return;
        awaitingStartPoint = false;
        directionsPending = true;
        requireLocation(() => {
            directionsPending = false;
            if (fixValid) {
                routeFrom(fix.lat, fix.lon);
                return;
            }
            if (location)
                location.start();
            _askForStart();
        });
    }

    function _askForStart() {
        awaitingStartPoint = true;
        _toMap();
    }

    function _toMap() {
        if (pageStack.depth > 1)
            pageStack.pop(pageStack.find(p => p.objectName === "mapPage"));
    }

    function _routeReady(geojson, maneuvers, durationSec, distanceM, summary) {
        currentRoute = { geojson: geojson, maneuvers: maneuvers, duration: durationSec, distance: distanceM, summary: summary };
        _coords = Logic.routeCoords(geojson);
        currentManeuverIndex = 0;
        nextDistance = -1;
        _cued = false;
        if (routingMode !== "active")
            routingMode = "preview";
        mapCall("setRouteGeoJSON", geojson);
        if (summary)
            mapCall("fitBounds", summary.minLon, summary.minLat, summary.maxLon, summary.maxLat, 80);
        if (routingMode === "preview" && (!pageStack.currentPage || pageStack.currentPage.objectName !== "routePage"))
            pageStack.push(Qt.resolvedUrl("pages/RoutePage.qml"), { app: root });
    }

    function say(maneuver, post) {
        if (!maneuver || !voice || !voice.available || voice.muted)
            return;
        const text = post ? maneuver.verbalPost : maneuver.verbalPre;
        if (text || !post)
            voice.speak(text || maneuver.instruction);
    }

    function startNavigation() {
        if (maneuvers.length === 0)
            return;
        requireLocation(() => {
            routingMode = "active";
            currentManeuverIndex = 0;
            nextDistance = -1;
            _cued = false;
            say(maneuvers[0], false);
            if (fixValid)
                _follow(fix.lat, fix.lon);
            _toMap();
        });
    }

    function endNavigation() {
        routingMode = "idle";
        currentRoute = null;
        _coords = [];
        currentManeuverIndex = 0;
        nextDistance = -1;
        mapCall("setRouteGeoJSON", { type: "FeatureCollection", features: [] });
        if (voice && voice.available)
            voice.stop();
    }

    function handleFix(lat, lon) {
        mapCall("setUserLocation", lat, lon);
        if (routingMode === "active") {
            mapCall("setCenter", lat, lon, 17);
            _follow(lat, lon);
        } else if (!selectedPlace) {
            mapCall("setCenter", lat, lon);
        }
        if (awaitingStartPoint)
            requestDirections();
    }

    function _follow(lat, lon) {
        const t = Logic.track(_coords, maneuvers, currentManeuverIndex, lat, lon);
        if (t.index !== currentManeuverIndex) {
            currentManeuverIndex = t.index;
            _cued = false;
            say(maneuvers[t.index], !Logic.isArrival(maneuvers[t.index]));
        }
        nextDistance = t.distance;
        if (!_cued && t.distance >= 0 && t.distance < Logic.cueRadius) {
            _cued = true;
            say(maneuvers[t.index + 1], false);
        }
    }

    // Unlike the default, back first steps out of the map's own states.
    function handleBack() {
        if (pageStack.depth > 1)
            pageStack.pop();
        else if (awaitingStartPoint)
            awaitingStartPoint = false;
        else if (routingMode === "preview")
            endNavigation();
        else if (routingMode === "idle" && selectedPlace)
            clearPlace();
        else
            minimizeRequested();
        return true;
    }

    function openSearch() {
        pageStack.push(Qt.resolvedUrl("pages/SearchPage.qml"), { app: root });
    }

    appId: "maps"
    onRoutingModeChanged: {
        if (!lifecycle)
            return;
        if (routingMode === "active" && _navTask === 0)
            _navTask = lifecycle.beginBackgroundTask("active-navigation", "turn-by-turn route");
        else if (routingMode !== "active" && _navTask !== 0) {
            lifecycle.endBackgroundTask(_navTask);
            _navTask = 0;
        }
    }
    Component.onCompleted: {
        try {
            voice = Qt.createQmlObject("import MarathonApp.Maps; VoiceClient {}", root, "VoiceClient");
        } catch (e) {
            console.info("Maps: no voice client; navigation cues will be silent");
        }
    }

    Connections {
        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId !== root.appId || permission !== "location")
                return;
            root.hasLocationPermission = true;
            if (root.location)
                root.location.start();
            const callback = root._pendingLocation;
            root._pendingLocation = null;
            if (callback)
                callback();
        }

        function onPermissionDenied(deniedAppId, permission) {
            if (deniedAppId !== root.appId || permission !== "location")
                return;
            root.hasLocationPermission = false;
            root._pendingLocation = null;
            if (root.directionsPending) {
                root.directionsPending = false;
                root._askForStart();
            } else {
                Notices.show(qsTr("Maps can't use your location. Allow location access to see where you are."));
            }
        }

        target: root.permissions
    }

    Connections {
        function onLocationChanged() {
            if (root.geoclueValid)
                root.handleFix(root.location.latitude, root.location.longitude);
        }

        target: root.location
    }

    Timer {
        interval: root.arrivalLinger
        running: root.arrived
        onTriggered: root.endNavigation()
    }

    QP.PositionSource {
        id: positionSource

        active: root.hasLocationPermission && !root.geoclueValid
        updateInterval: 5000
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid)
                root.handleFix(position.coordinate.latitude, position.coordinate.longitude);
        }
    }

    cover: Component {
        MapsCover {
            navigating: root.routingMode === "active"
            maneuver: root.nextManeuver
            distance: root.distanceToNext
            arrived: root.arrived
            place: root.selectedPlace
            onSearchRequested: {
                root.activate();
                root.openSearch();
            }
            voiceAvailable: root.voice !== null && root.voice.available
            muted: root.voice !== null && root.voice.muted
            onMuteToggled: root.voice.muted = !root.voice.muted
        }
    }

    initialPage: Component {
        MapPage {
            app: root
        }
    }
}
