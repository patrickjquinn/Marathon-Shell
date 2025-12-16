pragma Singleton
import MarathonOS.Shell
import QtQuick

Item {
    id: flashlightManager

    // Thin wrapper over C++ backend (no QML sysfs logic / mock mode).
    property bool available: (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.available : false
    property bool enabled: (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.enabled : false
    property int brightness: (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.brightness : 0
    property int maxBrightness: (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.maxBrightness : 0
    property string ledPath: (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.ledPath : ""
    property var availableLeds: [] // Deprecated; kept for API compatibility

    signal flashlightToggled(bool enabled)
    signal flashlightError(string error)

    function enable() {
        if (typeof FlashlightManagerCpp === "undefined" || !FlashlightManagerCpp) {
            flashlightError("Flashlight backend not available");
            return false;
        }
        FlashlightManagerCpp.enabled = true;
        flashlightToggled(true);
        return true;
    }

    function disable() {
        if (typeof FlashlightManagerCpp === "undefined" || !FlashlightManagerCpp)
            return false;

        FlashlightManagerCpp.enabled = false;
        flashlightToggled(false);
        return true;
    }

    function toggle() {
        if (typeof FlashlightManagerCpp === "undefined" || !FlashlightManagerCpp) {
            flashlightError("Flashlight backend not available");
            return false;
        }
        var newState = FlashlightManagerCpp.toggle();
        flashlightToggled(newState);
        return newState;
    }

    function setBrightness(value) {
        if (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp)
            FlashlightManagerCpp.brightness = value;
    }

    function pulse(durationMs) {
        if (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp)
            FlashlightManagerCpp.pulse(durationMs);
    }

    Component.onCompleted: {
        if (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp)
            FlashlightManagerCpp.errorOccurred.connect(function (msg) {
                flashlightError(msg);
            });
    }
}
