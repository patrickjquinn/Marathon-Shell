import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: tc

    name: "MapsApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    readonly property var place: ({ name: "Tower Bridge", address: "Tower Bridge, London, UK", lat: 10.002, lon: 1, type: "bridge" })
    readonly property var maneuvers: [
        { type: 1, beginShapeIndex: 0, instruction: "Head north.", verbalPre: "Head north.", verbalPost: "", length: 0.111, time: 20 },
        { type: 10, beginShapeIndex: 1, instruction: "Turn right onto High Street.", verbalPre: "Turn right onto High Street.", verbalPost: "Continue for 100 meters.", length: 0.111, time: 20, streetNames: ["High Street"] },
        { type: 4, beginShapeIndex: 2, instruction: "You have arrived.", verbalPre: "You have arrived.", verbalPost: "", length: 0, time: 0 }
    ]
    readonly property string geojson: JSON.stringify({ type: "FeatureCollection", features: [{ type: "Feature", geometry: { type: "LineString", coordinates: [[1, 10], [1, 10.001], [1, 10.002]] } }] })

    Component {
        id: appComponent

        MapsApp {
            width: 540
            height: 1140
            mapSource: Qt.resolvedUrl("MapStub.qml")
        }
    }

    function init() {
        Location.reset();
        Permissions.reset();
        Lifecycle.held = 0;
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, tc);
        tryVerify(() => app.pageStack.currentPage !== null && app.pageStack.currentPage.status === PageStatus.Active);
        tryVerify(() => app.map !== null);
        return app;
    }

    function settle(app) {
        tryVerify(() => !app.pageStack.busy && app.pageStack.currentPage.status === PageStatus.Active, 5000);
        // The page takes input from the next frame.
        wait(0);
    }

    function current(app) {
        return app.pageStack.currentPage;
    }

    function routed(app) {
        app.selectPlace(place);
        app.router.routing = false;
        app.router.routeReady(geojson, maneuvers, 40, 222, { minLat: 10, minLon: 1, maxLat: 10.002, maxLon: 1 });
        settle(app);
    }

    function test_queuesMapCallsUntilReady() {
        const app = makeApp();
        app.mapCall("setCenter", 1, 2, 3);
        compare(app.map.calls.length, 0);
        app.map.ready();
        verify(app.mapReady);
        verify(app.map.calls[0].indexOf("setCenter(1,2,3)") > 0);
        app.mapCall("clearPins");
        verify(app.map.calls[app.map.calls.length - 1].indexOf("clearPins()") > 0);
    }

    function test_mapError() {
        const app = makeApp();
        const error = findChild(current(app), "mapError");
        verify(!error.visible);
        app.map.failed("Style failed to load");
        verify(error.visible);
        verify(!findChild(current(app), "mapUnavailable").visible);
        mouseClick(findChild(current(app), "retryMap"));
        compare(app.map.reloads, 1);
        verify(!error.visible);
    }

    function test_mapWithoutWebGLPointsAtSearch() {
        const app = makeApp();
        app.map.failed("Failed to initialize WebGL");
        verify(!findChild(current(app), "mapError").visible);
        const note = findChild(current(app), "mapUnavailable");
        verify(note.visible);
        verify(note.y + note.height <= findChild(current(app), "bottomPanel").y);
        mouseClick(findChild(current(app), "unavailableSearch"));
        tryCompare(app.pageStack, "depth", 2);
        compare(app.map.reloads, 0);
    }

    function test_search() {
        const app = makeApp();
        let asked = "";
        app.fetch = (url, done) => {
            asked = url;
            done(200, JSON.stringify([{ display_name: "Tower Bridge, London", lat: "51.5", lon: "-0.07", type: "bridge" }]));
        };
        app.openSearch();
        settle(app);
        compare(current(app).objectName, "searchPage");
        const field = findChild(current(app), "searchField");
        field.text = "tower";
        tryVerify(() => app.searchResults.length === 1, 2000);
        verify(asked.indexOf("q=tower") > 0);
        const view = findChild(current(app), "resultsView");
        tryCompare(view, "count", 1);
        verify(!findChild(current(app), "placeholder").enabled);
        mouseClick(view.itemAtIndex(0));
        settle(app);
        compare(current(app).objectName, "placePage");
        compare(app.selectedPlace.name, "Tower Bridge");
        compare(app.pageStack.depth, 2);
    }

    function test_searchFailure() {
        const app = makeApp();
        app.fetch = (url, done) => done(0, "");
        app.search("tower");
        verify(!app.searching);
        verify(app.searchError.indexOf("internet") > 0);
        app.fetch = (url, done) => done(200, "{oops");
        app.search("tower");
        verify(app.searchError.length > 0);
        app.fetch = (url, done) => done(200, "[]");
        app.search("tower");
        compare(app.searchError, "");
        compare(app.searchResults, []);
    }

    function test_staleSearchIgnored() {
        const app = makeApp();
        let pending = null;
        app.fetch = (url, done) => pending = done;
        app.search("first");
        const stale = pending;
        app.search("second");
        stale(200, JSON.stringify([{ display_name: "First", lat: "1", lon: "1" }]));
        compare(app.searchResults, []);
        verify(app.searching);
        pending(200, "[]");
        verify(!app.searching);
    }

    function test_navigateRequestsRoute() {
        const app = makeApp();
        Location.moveTo(10, 1);
        app.selectPlace(place);
        app.pageStack.push(Qt.resolvedUrl("../pages/PlacePage.qml"), { app: app });
        settle(app);
        compare(findChild(current(app), "addressItem").value, place.address);
        mouseClick(findChild(current(app), "navigateButton"));
        compare(app.router.requests.length, 1);
        compare(app.router.requests[0].to, [10.002, 1]);
        compare(app.router.requests[0].mode, "auto");
        verify(!findChild(current(app), "navigateButton").enabled);
    }

    function test_noFixAsksForStartPoint() {
        const app = makeApp();
        app.selectPlace(place);
        app.pageStack.push(Qt.resolvedUrl("../pages/PlacePage.qml"), { app: app });
        settle(app);
        app.requestDirections();
        settle(app);
        compare(current(app).objectName, "mapPage");
        verify(app.awaitingStartPoint);
        verify(findChild(current(app), "startHint").visible);
        compare(Location.starts, 1);
        app.map.clicked(0, 0);
        verify(!app.awaitingStartPoint);
        compare(app.router.requests[0].from, [0, 0]);
    }

    function test_permissionFlow() {
        const app = makeApp();
        Permissions.granted = false;
        app.selectPlace(place);
        app.requestDirections();
        compare(Permissions.requests, ["location"]);
        compare(app.router.requests.length, 0);
        Location.moveTo(10, 1);
        Permissions.permissionGranted("maps", "location");
        compare(app.router.requests.length, 1);
    }

    function test_permissionDeniedAsksForStart() {
        const app = makeApp();
        Permissions.granted = false;
        app.selectPlace(place);
        app.requestDirections();
        Permissions.permissionDenied("maps", "location");
        verify(app.awaitingStartPoint);
    }

    function test_routePage() {
        const app = makeApp();
        app.map.ready();
        routed(app);
        compare(app.routingMode, "preview");
        compare(current(app).objectName, "routePage");
        compare(findChild(current(app), "maneuverView").count, 3);
        compare(findChild(current(app), "durationItem").value, "1 min");
        verify(app.map.calls.some(c => c.indexOf("setRouteGeoJSON") > 0));
        verify(app.map.calls.some(c => c.indexOf("fitBounds") > 0));
    }

    function test_modeChangeReroutes() {
        const app = makeApp();
        Location.moveTo(10, 1);
        app.selectPlace(place);
        app.requestDirections();
        routed(app);
        const modes = findChild(current(app), "modes");
        mouseClick(modes.children[1]);
        compare(app.currentMode, "pedestrian");
        compare(app.router.requests.length, 2);
        compare(app.router.requests[1].mode, "pedestrian");
        app.router.routing = false;
        app.router.routeReady(geojson, maneuvers, 80, 222, null);
        settle(app);
        compare(app.pageStack.depth, 2);
    }

    function test_turnByTurn() {
        const app = makeApp();
        Location.moveTo(10, 1);
        routed(app);
        mouseClick(findChild(current(app), "startButton"));
        settle(app);
        compare(app.routingMode, "active");
        compare(current(app).objectName, "mapPage");
        compare(Lifecycle.held, 1);
        compare(app.voice.spoken, ["Head north.", "Turn right onto High Street."]);
        const page = current(app);
        verify(findChild(page, "navBanner").visible);
        compare(findChild(page, "navInstruction").text, "Turn right onto High Street.");
        compare(findChild(page, "navDistance").text, "110 m");

        Location.moveTo(10.0005, 1);
        compare(app.currentManeuverIndex, 0);
        compare(findChild(page, "navDistance").text, "56 m");
        compare(app.voice.spoken.length, 2);

        Location.moveTo(10.00098, 1);
        compare(app.currentManeuverIndex, 1);
        compare(app.voice.spoken[2], "Continue for 100 meters.");
        compare(findChild(page, "navInstruction").text, "You have arrived.");

        Location.moveTo(10.002, 1);
        verify(app.arrived);
        compare(app.voice.spoken[app.voice.spoken.length - 1], "You have arrived.");
        compare(findChild(page, "navRemaining").text, "Arrived");

        mouseClick(findChild(page, "endButton"));
        compare(app.routingMode, "idle");
        compare(app.currentRoute, null);
        compare(Lifecycle.held, 0);
    }

    function test_mute() {
        const app = makeApp();
        Location.moveTo(10, 1);
        routed(app);
        app.voice.muted = true;
        app.startNavigation();
        settle(app);
        compare(app.voice.spoken, []);
        mouseClick(findChild(current(app), "muteButton"));
        verify(!app.voice.muted);
    }

    function test_backSteps() {
        const app = makeApp();
        routed(app);
        compare(app.pageStack.depth, 2);
        app.handleBack();
        settle(app);
        compare(app.pageStack.depth, 1);
        compare(app.routingMode, "preview");
        app.handleBack();
        compare(app.routingMode, "idle");
        verify(app.selectedPlace !== null);
        app.handleBack();
        compare(app.selectedPlace, null);
        let minimized = false;
        app.minimizeRequested.connect(() => minimized = true);
        app.handleBack();
        verify(minimized);
    }

    function test_searchPlaceholders() {
        const app = makeApp();
        app.fetch = (url, done) => done(0, "");
        app.openSearch();
        settle(app);
        const page = current(app);
        const placeholder = findChild(page, "placeholder");
        verify(placeholder.enabled);
        compare(placeholder.text, "Find a place");
        findChild(page, "searchField").text = "nowhere";
        tryVerify(() => app.lastQuery === "nowhere", 2000);
        compare(placeholder.text, "Search didn't work");
        let asked = "";
        app.fetch = (url, done) => {
            asked = url;
            done(200, "[]");
        };
        findChild(page, "retryItem").clicked();
        verify(asked.indexOf("q=nowhere") > 0);
        compare(placeholder.text, "No places found");
    }

    function test_clearRouteLeavesRoutePage() {
        const app = makeApp();
        routed(app);
        compare(current(app).objectName, "routePage");
        findChild(current(app), "endItem").clicked();
        settle(app);
        compare(current(app).objectName, "mapPage");
        compare(app.routingMode, "idle");
    }

    function test_coverFollowsNavigation() {
        const app = makeApp();
        Location.moveTo(10, 1);
        routed(app);
        app.startNavigation();
        settle(app);
        compare(app.nextManeuver.instruction, "Turn right onto High Street.");
        compare(Math.round(app.distanceToNext), 111);
    }
}
