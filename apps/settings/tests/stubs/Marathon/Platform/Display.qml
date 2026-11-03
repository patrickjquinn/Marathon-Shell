pragma Singleton
import QtQml

QtObject {
    property real brightness: 0.5
    property bool autoBrightnessEnabled: false
    property bool rotationLocked: false
    property bool rotationAvailable: true
    property bool lightSensorAvailable: true
    property bool torchAvailable: true
    property bool nightLightEnabled: false
    property int nightLightTemperature: 3400
    property string nightLightSchedule: "off"
    property int nightLightFrom: 1320
    property int nightLightTo: 420

    function setNightLightTimes(from, to) {
        nightLightFrom = from;
        nightLightTo = to;
    }

    function reset() {
        brightness = 0.5;
        autoBrightnessEnabled = false;
        rotationLocked = false;
        rotationAvailable = true;
        lightSensorAvailable = true;
        torchAvailable = true;
        nightLightEnabled = false;
        nightLightTemperature = 3400;
        nightLightSchedule = "off";
        nightLightFrom = 1320;
        nightLightTo = 420;
    }
}
