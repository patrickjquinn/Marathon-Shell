pragma Singleton
import QtQuick
import MarathonOS.Shell

Item {
    id: flashlightManager

    property bool available: false
    property bool enabled: false
    property int brightness: 255  // 0-255
    property int maxBrightness: 255

    property string ledPath: ""
    property var availableLeds: []

    signal flashlightToggled(bool enabled)
    signal flashlightError(string error)

    function enable() {
        Logger.info("FlashlightManager", "Enabling flashlight");

        if (!available) {
            Logger.warn("FlashlightManager", "No flashlight available");
            flashlightError("No flashlight available");
            return false;
        }

        if (Platform.isLinux) {
            _writeLedBrightness(brightness);
        }

        enabled = true;
        flashlightToggled(true);
        return true;
    }

    function disable() {
        Logger.info("FlashlightManager", "Disabling flashlight");

        if (!available) {
            return false;
        }

        if (Platform.isLinux) {
            _writeLedBrightness(0);
        }

        enabled = false;
        flashlightToggled(false);
        return true;
    }

    function toggle() {
        if (enabled) {
            return disable();
        } else {
            return enable();
        }
    }

    function setBrightness(value) {
        var clamped = Math.max(0, Math.min(maxBrightness, value));
        brightness = clamped;

        if (enabled && Platform.isLinux) {
            _writeLedBrightness(clamped);
        }
    }

    function pulse(durationMs) {
        if (!available)
            return;
        Logger.info("FlashlightManager", "Pulsing flashlight for " + durationMs + "ms");

        enable();
        Qt.callLater(function () {
            pulseTimer.interval = durationMs;
            pulseTimer.start();
        });
    }

    Timer {
        id: pulseTimer
        repeat: false
        onTriggered: disable()
    }

    function _discoverLeds() {
        if (!Platform.isLinux) {
            Logger.info("FlashlightManager", "LED control only available on Linux");
            return;
        }

        Logger.info("FlashlightManager", "Discovering LED devices");

        // Common LED paths for flashlights on mobile Linux devices
        var commonPaths = ["/sys/class/leds/torch", "/sys/class/leds/flashlight", "/sys/class/leds/white:torch", "/sys/class/leds/led:torch_0", "/sys/class/leds/torch_0", "/sys/class/leds/flash_0"];

        // Try to find an available LED
        for (var i = 0; i < commonPaths.length; i++) {
            var testPath = commonPaths[i];
            Logger.debug("FlashlightManager", "Testing LED path: " + testPath);

            // In production, we'd actually check if the file exists
            // For now, we'll assume the first common path works
            if (i === 0) {  // Simulate finding torch LED
                ledPath = testPath;
                available = true;
                availableLeds.push(testPath);

                // Read max brightness
                _readMaxBrightness();

                Logger.info("FlashlightManager", "Flashlight found: " + testPath);
                break;
            }
        }

        if (!available) {
            Logger.warn("FlashlightManager", "No flashlight LED found");
        }
    }

    function _readMaxBrightness() {
        // In production: read from {ledPath}/max_brightness
        // For simulation, assume 255
        maxBrightness = 255;
        brightness = 255;
    }

    function _writeLedBrightness(value) {
        if (!ledPath) {
            Logger.error("FlashlightManager", "No LED path configured");
            return;
        }

        Logger.debug("FlashlightManager", "Writing brightness: " + value + " to " + ledPath + "/brightness");

        // In production, this would write to sysfs:
        // echo {value} > {ledPath}/brightness
        //
        // We need a C++ helper for this as QML can't write to sysfs directly
        if (typeof FlashlightCpp !== 'undefined') {
            FlashlightCpp.setBrightness(ledPath, value);
        } else {
            Logger.warn("FlashlightManager", "FlashlightCpp not available - using mock mode");
        }
    }

    Component.onCompleted: {
        Logger.info("FlashlightManager", "Initialized");
        _discoverLeds();
    }
}
