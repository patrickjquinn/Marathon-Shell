pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: ambientLightSensor
    
    property bool available: false
    property bool active: false
    property real lightLevel: 500.0  // Lux
    property real minLux: 0.0
    property real maxLux: 10000.0
    
    property bool autoBrightnessEnabled: false
    property string sensorPath: ""
    
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
    
    signal lightLevelChanged(real lux)
    signal brightnessAdjusted(real brightness)
    signal sensorError(string error)
    
    function start() {
        if (!available) {
            Logger.warn("AmbientLightSensor", "Sensor not available")
            return false
        }
        
        Logger.info("AmbientLightSensor", "Starting ambient light sensor")
        active = true
        
        if (Platform.isLinux) {
            _startLinuxSensor()
        }
        
        pollTimer.start()
        return true
    }
    
    function stop() {
        Logger.info("AmbientLightSensor", "Stopping ambient light sensor")
        active = false
        pollTimer.stop()
        
        if (Platform.isLinux) {
            _stopLinuxSensor()
        }
        
        return true
    }
    
    function enableAutoBrightness() {
        Logger.info("AmbientLightSensor", "Enabling auto-brightness")
        autoBrightnessEnabled = true
        
        if (!active) {
            start()
        }
        
        // Set initial brightness based on current light
        _adjustBrightness(lightLevel)
    }
    
    function disableAutoBrightness() {
        Logger.info("AmbientLightSensor", "Disabling auto-brightness")
        autoBrightnessEnabled = false
        
        // Optionally stop sensor to save power
        if (active) {
            stop()
        }
    }
    
    function _discoverSensor() {
        if (!Platform.isLinux) {
            Logger.info("AmbientLightSensor", "Light sensors only supported on Linux")
            return
        }
        
        Logger.info("AmbientLightSensor", "Discovering ambient light sensor")
        
        // Common IIO paths for light sensors on mobile Linux
        var commonPaths = [
            "/sys/bus/iio/devices/iio:device0",
            "/sys/bus/iio/devices/iio:device1",
            "/sys/bus/iio/devices/iio:device2",
            "/sys/bus/iio/devices/iio:device3",
            "/sys/bus/iio/devices/iio:device4"
        ]
        
        // In production, check each device's 'name' file
        // Look for: tsl2561, apds9960, vcnl4000, isl29125, etc.
        //
        // For now, simulate finding a sensor
        for (var i = 0; i < commonPaths.length; i++) {
            // Simulate checking if this is a light sensor
            if (i === 0) {  // Assume device0 is light sensor
                sensorPath = commonPaths[i]
                available = true
                Logger.info("AmbientLightSensor", "Light sensor found: " + sensorPath)
                break
            }
        }
        
        if (!available) {
            Logger.warn("AmbientLightSensor", "No ambient light sensor found")
        }
    }
    
    function _startLinuxSensor() {
        if (!sensorPath) return
        
        Logger.debug("AmbientLightSensor", "Linux: Enabling IIO light sensor")
        
        // Enable the sensor via IIO
        // echo 1 > {sensorPath}/buffer/enable
        // cat {sensorPath}/in_illuminance_input
        
        if (typeof SensorManagerCpp !== 'undefined') {
            SensorManagerCpp.enableLightSensor(sensorPath)
        }
    }
    
    function _stopLinuxSensor() {
        if (!sensorPath) return
        
        Logger.debug("AmbientLightSensor", "Linux: Disabling IIO light sensor")
        
        if (typeof SensorManagerCpp !== 'undefined') {
            SensorManagerCpp.disableLightSensor(sensorPath)
        }
    }
    
    function _readSensor() {
        if (!active || !sensorPath) return
        
        // Read light level in lux
        // In production: read from {sensorPath}/in_illuminance_input
        //
        // This would be done via C++ helper
        if (typeof SensorManagerCpp !== 'undefined') {
            var lux = SensorManagerCpp.readLightLevel(sensorPath)
            _processSensorValue(lux)
        } else {
            // Mock data for testing - simulate day/night cycle
            var hour = new Date().getHours()
            var mockLux
            
            if (hour >= 6 && hour < 8) {
                mockLux = 50 + Math.random() * 200  // Dawn
            } else if (hour >= 8 && hour < 18) {
                mockLux = 300 + Math.random() * 2000  // Day
            } else if (hour >= 18 && hour < 20) {
                mockLux = 50 + Math.random() * 200  // Dusk
            } else {
                mockLux = 1 + Math.random() * 50  // Night
            }
            
            _processSensorValue(mockLux)
        }
    }
    
    function _processSensorValue(lux) {
        var oldLevel = lightLevel
        lightLevel = Math.max(minLux, Math.min(maxLux, lux))
        
        // Only log significant changes
        var percentChange = Math.abs((lightLevel - oldLevel) / oldLevel)
        if (percentChange > 0.2) {  // 20% change
            Logger.debug("AmbientLightSensor", "Light level: " + Math.round(lightLevel) + " lux")
            lightLevelChanged(lightLevel)
        }
        
        // Adjust brightness if auto-brightness enabled
        if (autoBrightnessEnabled && percentChange > 0.15) {  // 15% threshold for adjustment
            _adjustBrightness(lightLevel)
        }
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
    
    Timer {
        id: pollTimer
        interval: 2000  // Poll every 2 seconds (light changes slowly)
        repeat: true
        running: false
        onTriggered: _readSensor()
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
        _discoverSensor()
        
        // Start if auto-brightness already enabled
        if (DisplayManager.autoBrightnessEnabled) {
            enableAutoBrightness()
        }
    }
}

