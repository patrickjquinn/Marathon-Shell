pragma Singleton
import QtQuick
import MarathonOS.Shell

Item {
    id: ambientLightSensor

    property bool available: SensorManagerCpp.available
    property bool active: true
    property real lightLevel: SensorManagerCpp.ambientLight
    property real minLux: 0.0
    property real maxLux: 10000.0

    property bool autoBrightnessEnabled: false

    // Brightness mapping
    property var brightnessMap: [
        {maxLux: 10, brightness: 0.1},      // Very dark
        {maxLux: 50, brightness: 0.2},      // Dark room
        {maxLux: 100, brightness: 0.3},     // Dim room
        {maxLux: 300, brightness: 0.5},     // Office
        {maxLux: 1000, brightness: 0.7},    // Bright room
        {maxLux: 5000, brightness: 0.85},   // Sunlight indirect
        {maxLux: 999999, brightness: 1.0}   // Direct sunlight
    ]

    signal brightnessAdjusted(real value)

    function enableAutoBrightness() {
        autoBrightnessEnabled = true
        Logger.info("AmbientLightSensor", "Auto brightness enabled")
        _adjustBrightness(lightLevel)
    }

    function disableAutoBrightness() {
        autoBrightnessEnabled = false
        Logger.info("AmbientLightSensor", "Auto brightness disabled")
    }

    function _adjustBrightness(lux) {
        // Map lux to brightness using lookup table
        var brightness = 0.5  // Default

        for (var i = 0; i < brightnessMap.length; i++) {
            if (lux <= brightnessMap[i].maxLux) {
                brightness = brightnessMap[i].brightness
                break
            }
        }

        // Smooth brightness changes - apply a simple moving average
        var currentBrightness = DisplayManager.brightness
        var smoothed = currentBrightness * 0.7 + brightness * 0.3

        Logger.debug("AmbientLightSensor", "Auto-brightness: " + Math.round(smoothed * 100) + "% (lux: " + Math.round(lux) + ")")

        DisplayManager.setBrightness(smoothed)
        brightnessAdjusted(smoothed)
    }

    Connections {
        target: SensorManagerCpp
        function onAmbientLightChanged() {
            var lux = SensorManagerCpp.ambientLight
            lightLevel = Math.min(maxLux, Math.max(minLux, lux))
            _adjustBrightness(lightLevel)
        }
    }

    // Sync with DisplayManager auto-brightness setting
    Connections {
        target: DisplayManager

        function onAutoBrightnessEnabledChanged() {
            if (DisplayManager.autoBrightnessEnabled) {
                enableAutoBrightness()
            } else {
                disableAutoBrightness()
            }
        }
    }

    Component.onCompleted: {
        Logger.info("AmbientLightSensor", "Initialized")
        
        // Start if auto-brightness already enabled
        if (DisplayManager.autoBrightnessEnabled) {
            enableAutoBrightness()
        }
    }
}
