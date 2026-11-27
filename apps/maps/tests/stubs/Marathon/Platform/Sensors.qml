pragma Singleton
import QtQml

QtObject {
    property bool compassAvailable: true
    property bool compassWanted: false
    property real heading: -1
    property bool compassCalibrated: false

    signal compassChanged

    function face(degrees, calibrated) {
        heading = degrees;
        compassCalibrated = calibrated;
        compassChanged();
    }

    function reset() {
        compassAvailable = true;
        compassWanted = false;
        heading = -1;
        compassCalibrated = false;
    }
}
