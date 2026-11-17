import QtQuick
import Nemo.DBus 2.0

// marathon-radiod (org.marathonos.Radio1) for the app: its state as
// properties, kept current from StateChanged, and its calls as functions.
// Calls answering lists take a callback, as D-Bus answers arrive later.
Item {
    id: radio

    property var state: ({})
    // [latitude, longitude, name, stations] per place, for the globe.
    property var places: []
    readonly property bool ready: state.catalogue === "ready"
    readonly property bool failed: state.catalogue === "failed"
    readonly property var station: state.station || null
    readonly property bool playing: state.playing === true
    readonly property bool connecting: state.status === "connecting"
    readonly property bool broken: state.status === "failed"
    readonly property string title: state.title || ""
    readonly property string artist: state.artist || ""
    readonly property bool onFm: state.onFm === true
    readonly property bool headset: state.headset === true
    readonly property bool tuner: state.available === true
    readonly property bool scanning: state.scanning === true
    readonly property int frequency: state.frequency || 0
    // Where the phone's time zone puts it: the globe starts there.
    readonly property var home: state.home && state.home.length === 2 ? state.home : null

    signal placesLoaded

    // "1 station", "38 stations": English source strings have no plural
    // forms without a translation, so the two are spelled out.
    function stationCount(n) {
        return n === 1 ? qsTr("1 station") : qsTr("%1 stations").arg(n);
    }

    function megahertz(khz) {
        return (khz / 1000).toFixed(1);
    }

    function refresh() {
        bus.call("GetState", [], s => {
            return radio.state = s;
        });
    }

    function loadPlaces() {
        bus.call("Places", [], list => {
            radio.places = list;
            radio.placesLoaded();
        });
    }

    function placeStations(index, done) {
        bus.typedCall("PlaceStations", [
            {
                "type": "u",
                "value": index
            }
        ], done, () => {
            return done([]);
        });
    }

    function local(done) {
        bus.call("Local", [], done, () => {
            return done([]);
        });
    }

    function search(text, done) {
        bus.typedCall("Search", [
            {
                "type": "s",
                "value": text
            }
        ], done, () => {
            return done([]);
        });
    }

    function favourites(done) {
        bus.call("Favourites", [], done, () => {
            return done([]);
        });
    }

    function recents(done) {
        bus.call("Recents", [], done, () => {
            return done([]);
        });
    }

    // Plays `station`; `list`, the stations it was chosen from, is what
    // next and previous go through.
    function play(station, list) {
        const ids = (list || []).map(s => {
            return s.id;
        });
        bus.typedCall("Play", [
            {
                "type": "s",
                "value": station.id
            },
            {
                "type": "as",
                "value": ids
            }
        ]);
    }

    function tune(khz) {
        bus.typedCall("Tune", [
            {
                "type": "i",
                "value": khz
            }
        ]);
    }

    function toggle() {
        bus.call(playing ? "Stop" : "Resume", []);
    }

    function stop() {
        bus.call("Stop", []);
    }

    function next() {
        bus.call("Next", []);
    }

    function previous() {
        bus.call("Previous", []);
    }

    function scan() {
        bus.call("Scan", []);
    }

    function setFavourite(station, on) {
        bus.typedCall("SetFavourite", [
            {
                "type": "s",
                "value": station.id
            },
            {
                "type": "b",
                "value": on
            }
        ]);
    }

    onReadyChanged: {
        if (ready && places.length === 0)
            loadPlaces();
    }

    DBusInterface {
        id: bus

        function stateChanged(s) {
            radio.state = s;
        }

        service: "org.marathonos.Radio"
        path: "/org/marathonos/Radio"
        iface: "org.marathonos.Radio1"
        signalsEnabled: true
        Component.onCompleted: radio.refresh()
    }
}
