import QtQuick
import QtTest
import "../MapsLogic.js" as Logic

TestCase {
    name: "MapsLogic"

    // Three points ~111 m apart going north.
    readonly property var coords: [[0, 0], [0, 0.001], [0, 0.002]]
    readonly property var maneuvers: [
        { type: 1, beginShapeIndex: 0, instruction: "Head north." },
        { type: 10, beginShapeIndex: 1, instruction: "Turn right." },
        { type: 4, beginShapeIndex: 2, instruction: "You have arrived." }
    ]

    function test_parseResults() {
        const r = Logic.parseResults(JSON.stringify([
            { display_name: "Tower Bridge, London, UK", lat: "51.5055", lon: "-0.0754", type: "bridge_x" },
            { display_name: "Nowhere", lat: "x", lon: "1" }
        ]));
        compare(r.length, 1);
        compare(r[0].name, "Tower Bridge");
        compare(r[0].address, "Tower Bridge, London, UK");
        compare(r[0].lat, 51.5055);
        compare(r[0].type, "bridge x");
    }

    function test_parseResultsBad() {
        compare(Logic.parseResults("{oops"), null);
        compare(Logic.parseResults("{}"), null);
        compare(Logic.parseResults("[]"), []);
    }

    function test_formatDistance() {
        compare(Logic.formatDistance(42.4), "42 m");
        compare(Logic.formatDistance(456), "460 m");
        compare(Logic.formatDistance(1234), "1.2 km");
        compare(Logic.formatDistance(-5), "0 m");
    }

    function test_formatDuration() {
        compare(Logic.formatDuration(20), "1 min");
        compare(Logic.formatDuration(25 * 60), "25 min");
        compare(Logic.formatDuration(125 * 60), "2 h 5 min");
    }

    function test_maneuverIcon() {
        compare(Logic.maneuverIcon(10), "image://theme/icon-m-maneuver-right");
        compare(Logic.maneuverIcon(15), "image://theme/icon-m-maneuver-left");
        compare(Logic.maneuverIcon(4), "image://theme/icon-m-maneuver-arrive");
        compare(Logic.maneuverIcon(8), "image://theme/icon-m-maneuver-straight");
        verify(Logic.isArrival({ type: 5 }));
        verify(!Logic.isArrival({ type: 10 }));
        verify(!Logic.isArrival(null));
    }

    function test_routeCoords() {
        const fc = { type: "FeatureCollection", features: [{ type: "Feature", geometry: { type: "LineString", coordinates: coords } }] };
        compare(Logic.routeCoords(JSON.stringify(fc)), coords);
        compare(Logic.routeCoords(fc), coords);
        compare(Logic.routeCoords("nope"), []);
    }

    function test_distance() {
        fuzzyCompare(Logic.distanceMeters(0, 0, 0.001, 0), 111.2, 0.5);
    }

    function test_trackApproaching() {
        const t = Logic.track(coords, maneuvers, 0, 0.0005, 0);
        compare(t.index, 0);
        fuzzyCompare(t.distance, 55.6, 0.5);
    }

    function test_trackAdvances() {
        const t = Logic.track(coords, maneuvers, 0, 0.00095, 0);
        compare(t.index, 1);
        fuzzyCompare(t.distance, 116.8, 0.5);
        const end = Logic.track(coords, maneuvers, 1, 0.002, 0);
        compare(end.index, 2);
        compare(end.distance, -1);
    }

    function test_trackNeverGoesBack() {
        compare(Logic.track(coords, maneuvers, 1, 0, 0).index, 1);
    }

    function test_via() {
        compare(Logic.via([{}, { streetNames: ["High St", "A1"] }]), "High St, A1");
        compare(Logic.via([{}]), "");
        compare(Logic.via(null), "");
    }

    function test_remaining() {
        const ms = [{ length: 1, time: 100 }, { length: 0.5, time: 50 }, { length: 0, time: 0 }];
        compare(Logic.remaining(ms, 0, -1), { distance: 1500, time: 150 });
        compare(Logic.remaining(ms, 0, 500), { distance: 1000, time: 100 });
        compare(Logic.remaining(ms, 2, -1), { distance: 0, time: 0 });
        compare(Logic.remaining(null, 0, -1), { distance: 0, time: 0 });
    }

    function test_placeKindAndLine() {
        compare(Logic.placeKind("bridge"), "Bridge");
        compare(Logic.placeKind("yes"), "");
        compare(Logic.placeKind(""), "");
        compare(Logic.placeLine({ name: "Tower Bridge", address: "Tower Bridge, London, UK", type: "bridge" }), "Bridge · London, UK");
        compare(Logic.placeLine({ name: "Home", address: "Home, 1 Road", type: "yes" }), "1 Road");
        compare(Logic.placeLine({ name: "X", address: "", type: "cafe" }), "Café");
    }

    function test_addRecent() {
        const a = { name: "A", address: "A, X", lat: 1, lon: 1 };
        const b = { name: "B", address: "B, X", lat: 2, lon: 2 };
        let r = Logic.addRecent([], a);
        r = Logic.addRecent(r, b);
        r = Logic.addRecent(r, a);
        compare(r.map(p => p.name), ["A", "B"]);
        for (let i = 0; i < 20; i++)
            r = Logic.addRecent(r, { name: "P" + i, address: "", lat: i, lon: 0 });
        compare(r.length, 10);
        compare(Logic.parseList("nope"), []);
    }

    function test_parseFix() {
        compare(Logic.parseFix('{"lat":1,"lon":2}'), { lat: 1, lon: 2 });
        compare(Logic.parseFix(""), null);
        compare(Logic.parseFix('{"lat":"x"}'), null);
    }

    function test_mapFailureIsPermanent() {
        verify(Logic.mapFailureIsPermanent("Failed to initialize WebGL"));
        verify(Logic.mapFailureIsPermanent("Could not create a WebGL context"));
        verify(!Logic.mapFailureIsPermanent("Style failed to load"));
    }
}
