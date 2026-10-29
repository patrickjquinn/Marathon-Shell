import QtQml

QtObject {
    property bool routing: false
    property var requests: []

    signal routeReady(string geojson, var maneuvers, real durationSec, real distanceMeters, var summary)
    signal routeFailed(string error)

    function requestRoute(startLat, startLon, endLat, endLon, mode) {
        requests = requests.concat([
            {
                from: [startLat, startLon],
                to: [endLat, endLon],
                mode: mode
            }
        ]);
        routing = true;
    }

    function clearRoute() {
    }
}
