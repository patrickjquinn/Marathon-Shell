pragma Singleton
import QtQml

QtObject {
    property bool available: true
    property real latitude: 0
    property real longitude: 0
    property real accuracy: 10
    property int starts: 0

    signal locationChanged

    function start() {
        starts++;
    }

    function moveTo(lat, lon) {
        latitude = lat;
        longitude = lon;
        locationChanged();
    }

    function reset() {
        available = true;
        latitude = 0;
        longitude = 0;
        starts = 0;
    }
}
