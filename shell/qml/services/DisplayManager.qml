pragma Singleton
import MarathonOS.Shell
import QtQuick

QtObject {
    // Thin wrapper over C++ backend + C++ policy controller (Deepak: no QML policy glue)
    // Keep this singleton for API stability in QML, but delegate logic to C++.

    id: displayManager

    property real brightness: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.brightness : 0.75
    property bool autoBrightnessEnabled: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.autoBrightnessEnabled : false
    property bool screenOn: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenOn : true
    // Screen timeout is in milliseconds (source of truth: SettingsManagerCpp)
    property int screenTimeout: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenTimeoutMs : (typeof SettingsManagerCpp !== "undefined" ? SettingsManagerCpp.screenTimeout : 120000)
    readonly property string screenTimeoutString: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenTimeoutString : ""
    // Leave remaining fields as UI-only placeholders (may be migrated later)
    property bool ambientDisplayEnabled: false
    property string orientation: "portrait"
    property bool rotationLocked: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.rotationLocked : false
    property var availableOrientations: ["portrait", "landscape", "portrait-inverted", "landscape-inverted"]
    property int displayWidth: 720
    property int displayHeight: 1280
    property real displayDpi: 320
    property real refreshRate: 60
    property Connections rotationConnections

    signal brightnessSet(real value)
    signal autoBrightnessChanged(bool enabled)
    signal orientationSet(string orientation)
    signal screenStateChanged(bool on)

    function setBrightness(value) {
        if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) {
            DisplayManagerCpp.brightness = value;
            brightnessSet(DisplayManagerCpp.brightness);
        } else {
            brightness = value;
            brightnessSet(value);
        }
    }

    function increaseBrightness(step) {
        setBrightness(brightness + (step || 0.1));
    }

    function decreaseBrightness(step) {
        setBrightness(brightness - (step || 0.1));
    }

    function setAutoBrightness(enabled) {
        if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
            DisplayPolicyControllerCpp.autoBrightnessEnabled = enabled;
        else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.setAutoBrightness(enabled);
        autoBrightnessChanged(enabled);
    }

    function setOrientation(orient) {
        if (availableOrientations.indexOf(orient) === -1) {
            console.warn("[DisplayManager] Invalid orientation:", orient);
            return;
        }
        console.log("[DisplayManager] Setting orientation:", orient);
        orientation = orient;
        orientationSet(orient);
    }

    function setRotationLock(locked) {
        console.log("[DisplayManager] Rotation lock:", locked);
        rotationLocked = locked;
        if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.setRotationLock(locked);
    }

    function setScreenTimeout(milliseconds) {
        console.log("[DisplayManager] Screen timeout:", milliseconds);
        if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
            DisplayPolicyControllerCpp.screenTimeoutMs = milliseconds;
        else if (typeof SettingsManagerCpp !== "undefined")
            SettingsManagerCpp.screenTimeout = milliseconds;
    }

    function turnScreenOn() {
        console.log("[DisplayManager] Turning screen on...");
        if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
            DisplayPolicyControllerCpp.turnScreenOn();
        else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.setScreenState(true);
        screenOn = true;
        screenStateChanged(true);
    }

    function turnScreenOff() {
        console.log("[DisplayManager] Turning screen off...");
        if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
            DisplayPolicyControllerCpp.turnScreenOff();
        else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.setScreenState(false);
        screenOn = false;
        screenStateChanged(false);
    }

    rotationConnections: Connections {
        function onOrientationChanged() {
            console.log("[DisplayManager] Detected orientation change from system:", RotationManager.currentOrientation);
            if (!displayManager.rotationLocked) {
                displayManager.orientation = RotationManager.currentOrientation;
                displayManager.orientationSet(displayManager.orientation);
            }
        }

        target: typeof RotationManager !== 'undefined' ? RotationManager : null
        ignoreUnknownSignals: true
    }
}
