pragma Singleton
import QtQml

QtObject {
    property real brightness: 0.5
    property bool autoBrightnessEnabled: false
    property bool rotationLocked: false
    // Seconds, as the shell's display manager keeps it.
    property int screenTimeout: 60
    readonly property string screenTimeoutString: screenTimeout === 0 ? "Never" : screenTimeout + " s"

    function reset() {
        brightness = 0.5;
        autoBrightnessEnabled = false;
        rotationLocked = false;
        screenTimeout = 60;
    }
}
