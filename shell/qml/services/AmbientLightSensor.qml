pragma Singleton
import MarathonOS.Shell
import QtQuick

Item {
    // Very dark
    // Dark room
    // Dim room
    // Office
    // Bright room
    // Sunlight indirect
    // Direct sunlight
    // Default

    id: ambientLightSensor

    property bool available: SensorManagerCpp.available
    property bool active: true
    property real lightLevel: SensorManagerCpp.ambientLight
    property real minLux: 0
    property real maxLux: 10000
    property bool autoBrightnessEnabled: false
    // Brightness mapping
    property var brightnessMap: [
        {
            "maxLux": 10,
            "brightness": 0.1
        },
        {
            "maxLux": 50,
            "brightness": 0.2
        },
        {
            "maxLux": 100,
            "brightness": 0.3
        },
        {
            "maxLux": 300,
            "brightness": 0.5
        },
        {
            "maxLux": 1000,
            "brightness": 0.7
        },
        {
            "maxLux": 5000,
            "brightness": 0.85
        },
        {
            "maxLux": 999999,
            "brightness": 1
        }
    ]

    signal brightnessAdjusted(real value)

    function enableAutoBrightness() {
        autoBrightnessEnabled = true;
        Logger.info("AmbientLightSensor", "Auto brightness enabled");
        _adjustBrightness(lightLevel);
    }

    function disableAutoBrightness() {
        autoBrightnessEnabled = false;
        Logger.info("AmbientLightSensor", "Auto brightness disabled");
    }

    function _adjustBrightness(lux) {
        // Map lux to brightness using lookup table
        var brightness = 0.5;
        for (var i = 0; i < brightnessMap.length; i++) {
            if (lux <= brightnessMap[i].maxLux) {
                brightness = brightnessMap[i].brightness;
                break;
            }
        }
        // Smooth brightness changes - apply a simple moving average
        var currentBrightness = DisplayManager.brightness;
        var smoothed = currentBrightness * 0.7 + brightness * 0.3;
        Logger.debug("AmbientLightSensor", "Auto-brightness: " + Math.round(smoothed * 100) + "% (lux: " + Math.round(lux) + ")");
        DisplayManager.setBrightness(smoothed);
        brightnessAdjusted(smoothed);
    }

    Component.onCompleted: {
        Logger.info("AmbientLightSensor", "Initialized");
        // Start if auto-brightness already enabled
        if (DisplayManager.autoBrightnessEnabled)
            enableAutoBrightness();
    }

    Connections {
        function onAmbientLightChanged() {
            var lux = SensorManagerCpp.ambientLight;
            lightLevel = Math.min(maxLux, Math.max(minLux, lux));
            _adjustBrightness(lightLevel);
        }

        target: SensorManagerCpp
    }

    // Sync with DisplayManager auto-brightness setting
    Connections {
        function onAutoBrightnessEnabledChanged() {
            if (DisplayManager.autoBrightnessEnabled)
                enableAutoBrightness();
            else
                disableAutoBrightness();
        }

        target: DisplayManager
    }
}
