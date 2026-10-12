pragma Singleton
import QtQml

QtObject {
    property real brightness: 0.5
    property bool autoBrightnessEnabled: false
    property bool rotationLocked: false
    property int screenTimeout: 60000
    readonly property string screenTimeoutString: screenTimeout === 0 ? "Never" : (screenTimeout / 1000) + " s"

    function reset() {
        brightness = 0.5;
        autoBrightnessEnabled = false;
        rotationLocked = false;
        screenTimeout = 60000;
    }
}
