pragma Singleton
import QtQml

QtObject {
    property real brightness: 0.5
    property bool autoBrightnessEnabled: false
    property bool rotationLocked: false
    property bool rotationAvailable: true
    property bool lightSensorAvailable: true
    property bool torchAvailable: true

    function reset() {
        brightness = 0.5;
        autoBrightnessEnabled = false;
        rotationLocked = false;
        rotationAvailable = true;
        lightSensorAvailable = true;
        torchAvailable = true;
    }
}
