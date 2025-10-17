pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: proximitySensor
    
    property bool available: false
    property bool active: false
    property bool near: false  // Object near sensor
    property real distance: 100.0  // Distance in cm (if supported)
    property real threshold: 5.0  // cm - below this is "near"
    
    property bool autoScreenOff: true  // Auto turn off screen when near
    property string sensorPath: ""
    
    signal proximityChanged(bool near, real distance)
    signal sensorError(string error)
    
    function start() {
        if (!available) {
            Logger.warn("ProximitySensor", "Sensor not available")
            return false
        }
        
        Logger.info("ProximitySensor", "Starting proximity sensor")
        active = true
        
        if (Platform.isLinux) {
            _startLinuxSensor()
        }
        
        pollTimer.start()
        return true
    }
    
    function stop() {
        Logger.info("ProximitySensor", "Stopping proximity sensor")
        active = false
        pollTimer.stop()
        
        if (Platform.isLinux) {
            _stopLinuxSensor()
        }
        
        return true
    }
    
    function setThreshold(cm) {
        threshold = Math.max(0, cm)
        Logger.info("ProximitySensor", "Proximity threshold set to: " + threshold + " cm")
    }
    
    function _discoverSensor() {
        if (!Platform.isLinux) {
            Logger.info("ProximitySensor", "Proximity sensors only supported on Linux")
            return
        }
        
        Logger.info("ProximitySensor", "Discovering proximity sensor")
        
        // Common IIO paths for proximity sensors on mobile Linux
        var commonPaths = [
            "/sys/bus/iio/devices/iio:device0",
            "/sys/bus/iio/devices/iio:device1",
            "/sys/bus/iio/devices/iio:device2",
            "/sys/bus/iio/devices/iio:device3"
        ]
        
        // In production, we'd check each device's 'name' file for proximity sensor
        // Look for: vcnl4000, apds9960, stk3310, etc.
        //
        // For now, simulate finding a sensor
        for (var i = 0; i < commonPaths.length; i++) {
            // Simulate checking if this is a proximity sensor
            if (i === 1) {  // Assume device1 is proximity
                sensorPath = commonPaths[i]
                available = true
                Logger.info("ProximitySensor", "Proximity sensor found: " + sensorPath)
                break
            }
        }
        
        if (!available) {
            Logger.warn("ProximitySensor", "No proximity sensor found")
        }
    }
    
    function _startLinuxSensor() {
        if (!sensorPath) return
        
        Logger.debug("ProximitySensor", "Linux: Enabling IIO proximity sensor")
        
        // Enable the sensor via IIO
        // echo 1 > {sensorPath}/buffer/enable
        // cat {sensorPath}/in_proximity_raw
        
        if (typeof SensorManagerCpp !== 'undefined') {
            SensorManagerCpp.enableProximitySensor(sensorPath)
        }
    }
    
    function _stopLinuxSensor() {
        if (!sensorPath) return
        
        Logger.debug("ProximitySensor", "Linux: Disabling IIO proximity sensor")
        
        if (typeof SensorManagerCpp !== 'undefined') {
            SensorManagerCpp.disableProximitySensor(sensorPath)
        }
    }
    
    function _readSensor() {
        if (!active || !sensorPath) return
        
        // Read proximity value
        // In production: read from {sensorPath}/in_proximity_raw
        //
        // This would be done via C++ helper
        if (typeof SensorManagerCpp !== 'undefined') {
            var value = SensorManagerCpp.readProximity(sensorPath)
            _processSensorValue(value)
        } else {
            // Mock data for testing
            // Simulate random proximity events
            if (Math.random() < 0.01) {  // 1% chance per poll
                var mockNear = !near
                _processSensorValue(mockNear ? 0 : 100)
            }
        }
    }
    
    function _processSensorValue(rawValue) {
        // Convert raw value to distance (sensor-specific)
        // For now, assume: 0 = near, >0 = far
        var newDistance = rawValue
        var newNear = rawValue < threshold
        
        if (newNear !== near) {
            near = newNear
            distance = newDistance
            
            Logger.info("ProximitySensor", "Proximity: " + (near ? "NEAR" : "FAR") + " (" + distance + " cm)")
            proximityChanged(near, distance)
            
            // Auto screen off during calls
            if (autoScreenOff && typeof TelephonyManager !== 'undefined' && TelephonyManager.hasActiveCall) {
                if (near && DisplayManager.screenOn) {
                    Logger.info("ProximitySensor", "Auto screen OFF (phone near face)")
                    DisplayManager.turnScreenOff()
                } else if (!near && !DisplayManager.screenOn) {
                    Logger.info("ProximitySensor", "Auto screen ON (phone away from face)")
                    DisplayManager.turnScreenOn()
                }
            }
        }
    }
    
    Timer {
        id: pollTimer
        interval: 200  // Poll 5 times per second
        repeat: true
        running: false
        onTriggered: _readSensor()
    }
    
    // Auto-start proximity sensor during active calls
    Connections {
        target: typeof TelephonyManager !== 'undefined' ? TelephonyManager : null
        
        function onCallStarted(callId) {
            if (available && !active) {
                Logger.info("ProximitySensor", "Auto-starting for active call")
                start()
            }
        }
        
        function onCallEnded(callId) {
            if (active && !TelephonyManager.hasActiveCall) {
                Logger.info("ProximitySensor", "Auto-stopping (no active calls)")
                stop()
                
                // Ensure screen is on
                if (!DisplayManager.screenOn) {
                    DisplayManager.turnScreenOn()
                }
            }
        }
    }
    
    Component.onCompleted: {
        Logger.info("ProximitySensor", "Initialized")
        _discoverSensor()
    }
}

