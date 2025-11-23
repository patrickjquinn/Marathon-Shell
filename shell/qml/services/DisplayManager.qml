pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: displayManager
    
    property real brightness: 0.75
    property real minBrightness: 0.1
    property real maxBrightness: 1.0
    
    property bool autoBrightnessEnabled: false  // Managed by binding below
    
    // Two-way binding with restore mode (as property)
    property Binding autoBrightnessBinding: Binding {
        target: displayManager
        property: "autoBrightnessEnabled"
        value: SettingsManagerCpp.autoBrightness
        restoreMode: Binding.RestoreBinding
    }
    property bool nightModeEnabled: false
    property int nightModeTemperature: 3400
    
    property bool screenOn: true
    property int screenTimeout: SettingsManagerCpp.screenTimeout
    property bool ambientDisplayEnabled: false
    
    property string orientation: "portrait"
    property bool rotationLocked: false
    property var availableOrientations: ["portrait", "landscape", "portrait-inverted", "landscape-inverted"]
    
    property int displayWidth: 720
    property int displayHeight: 1280
    property real displayDpi: 320
    property real refreshRate: 60.0
    
    // Computed property for UI display
    readonly property string screenTimeoutString: {
        if (screenTimeout === 0) return "Never"
        if (screenTimeout === 30000) return "30 seconds"
        if (screenTimeout === 60000) return "1 minute"
        if (screenTimeout === 120000) return "2 minutes"
        if (screenTimeout === 300000) return "5 minutes"
        return Math.round(screenTimeout / 1000) + " seconds"
    }
    
    signal brightnessSet(real value)
    signal autoBrightnessChanged(bool enabled)
    signal nightModeChanged(bool enabled)
    signal orientationSet(string orientation)
    signal screenStateChanged(bool on)
    
    // Wire property changes to SettingsManager for persistence
    onAutoBrightnessEnabledChanged: {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp.autoBrightness !== autoBrightnessEnabled) {
            SettingsManagerCpp.autoBrightness = autoBrightnessEnabled
        }
    }
    
    onScreenTimeoutChanged: {
        if (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp.screenTimeout !== screenTimeout) {
            SettingsManagerCpp.screenTimeout = screenTimeout
        }
    }
    
    property Connections brightnessConnections: Connections {
        target: typeof DisplayManagerCpp !== 'undefined' ? DisplayManagerCpp : null
        ignoreUnknownSignals: true
        function onBrightnessChanged() {
            if (typeof DisplayManagerCpp === 'undefined') return
            
            var newBrightness = DisplayManagerCpp.brightness
            // Only sync if the difference is significant
            if (Math.abs(displayManager.brightness - newBrightness) > 0.01) {
                console.log("[DisplayManager] Syncing brightness from system:", newBrightness)
                displayManager.brightness = newBrightness
                displayManager.brightnessSet(newBrightness)
            }
        }
    }
    
    function setBrightness(value) {
        var clamped = Math.max(minBrightness, Math.min(maxBrightness, value))
        // console.log("[DisplayManager] Setting brightness:", clamped)
        brightness = clamped
        brightnessSet(clamped)
        _platformSetBrightness(clamped)
    }
    
    function increaseBrightness(step) {
        setBrightness(brightness + (step || 0.1))
    }
    
    function decreaseBrightness(step) {
        setBrightness(brightness - (step || 0.1))
    }
    
    function setAutoBrightness(enabled) {
        console.log("[DisplayManager] Auto-brightness:", enabled)
        autoBrightnessEnabled = enabled
        autoBrightnessChanged(enabled)
        _platformSetAutoBrightness(enabled)
    }
    
    function setNightMode(enabled) {
        console.log("[DisplayManager] Night mode:", enabled)
        nightModeEnabled = enabled
        nightModeChanged(enabled)
        _platformSetNightMode(enabled, nightModeTemperature)
    }
    
    function setNightModeTemperature(temp) {
        nightModeTemperature = Math.max(1000, Math.min(6500, temp))
        if (nightModeEnabled) {
            _platformSetNightMode(true, nightModeTemperature)
        }
    }
    
    function setOrientation(orient) {
        if (availableOrientations.indexOf(orient) === -1) {
            console.warn("[DisplayManager] Invalid orientation:", orient)
            return
        }
        
        console.log("[DisplayManager] Setting orientation:", orient)
        orientation = orient
        orientationSet(orient)
        _platformSetOrientation(orient)
    }
    
    function setRotationLock(locked) {
        console.log("[DisplayManager] Rotation lock:", locked)
        rotationLocked = locked
        _platformSetRotationLock(locked)
    }
    
    function setScreenTimeout(milliseconds) {
        console.log("[DisplayManager] Screen timeout:", milliseconds)
        screenTimeout = milliseconds
        _platformSetScreenTimeout(milliseconds)
    }
    
    function turnScreenOn() {
        console.log("[DisplayManager] Turning screen on...")
        screenOn = true
        screenStateChanged(true)
        _platformSetScreenState(true)
    }
    
    function turnScreenOff() {
        console.log("[DisplayManager] Turning screen off...")
        screenOn = false
        screenStateChanged(false)
        _platformSetScreenState(false)
    }
    
    function _platformSetBrightness(value) {
        if (Platform.isLinux && typeof DisplayManagerCpp !== 'undefined') {
            DisplayManagerCpp.brightness = value  // Use property assignment, not function call
        } else if (Platform.isMacOS) {
            console.log("[DisplayManager] macOS brightness via IOKit")
        }
    }
    
    function _platformSetAutoBrightness(enabled) {
        if (Platform.isLinux && typeof DisplayManagerCpp !== 'undefined') {
            DisplayManagerCpp.setAutoBrightness(enabled)
        } else if (Platform.isMacOS) {
            console.log("[DisplayManager] macOS auto-brightness system preference")
        }
    }
    
    function _platformSetNightMode(enabled, temperature) {
        if (Platform.isLinux) {
            console.log("[DisplayManager] Night mode via Redshift/Gammastep:", enabled, temperature)
        } else if (Platform.isMacOS) {
            console.log("[DisplayManager] macOS Night Shift:", enabled)
        }
    }
    
    function _platformSetOrientation(orient) {
        if (Platform.isLinux) {
            console.log("[DisplayManager] Setting orientation via xrandr/wlr-randr:", orient)
        }
    }
    
    function _platformSetRotationLock(locked) {
        if (Platform.isLinux) {
            console.log("[DisplayManager] Rotation lock via sensor control")
        }
    }
    
    function _platformSetScreenTimeout(ms) {
        if (Platform.hasSystemdLogind) {
            console.log("[DisplayManager] Screen timeout via logind IdleAction")
        } else if (Platform.isMacOS) {
            console.log("[DisplayManager] macOS pmset displaysleep", ms / 60000)
        }
    }
    
    function _platformSetScreenState(on) {
        if (Platform.isLinux && typeof DisplayManagerCpp !== 'undefined') {
            DisplayManagerCpp.setScreenState(on)
        } else if (Platform.isMacOS) {
            console.log("[DisplayManager] macOS screen state:", on)
        }
    }
    
    Component.onCompleted: {
        console.log("[DisplayManager] Initialized")
        console.log("[DisplayManager] Display:", displayWidth + "x" + displayHeight + "@" + refreshRate + "Hz")
        
        // Sync initial brightness from system
        if (typeof DisplayManagerCpp !== 'undefined') {
            var initialBrightness = DisplayManagerCpp.brightness
            console.log("[DisplayManager] Initial brightness from system:", initialBrightness)
            brightness = initialBrightness
            // Don't call setBrightness here to avoid loop on startup
        }
    }
}

