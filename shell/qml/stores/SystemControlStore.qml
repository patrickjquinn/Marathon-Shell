pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: systemControl
    
    property bool isWifiOn: NetworkManager.wifiEnabled
    property bool isBluetoothOn: NetworkManager.bluetoothEnabled
    property bool isAirplaneModeOn: NetworkManager.airplaneModeEnabled
    property bool isRotationLocked: DisplayManager.rotationLocked
    property bool isFlashlightOn: typeof FlashlightManager !== 'undefined' ? FlashlightManager.enabled : false
    property bool isCellularOn: typeof CellularManager !== 'undefined' ? CellularManager.modemEnabled : false
    property bool isCellularDataOn: typeof CellularManager !== 'undefined' ? CellularManager.dataEnabled : false
    property bool isDndMode: AudioManager.dndEnabled
    property bool isAlarmOn: typeof AlarmManager !== 'undefined' ? (AlarmManager.hasActiveAlarm || _hasEnabledAlarm()) : false
    
    function _hasEnabledAlarm() {
        if (typeof AlarmManager !== 'undefined' && AlarmManager.alarms) {
            for (var i = 0; i < AlarmManager.alarms.length; i++) {
                if (AlarmManager.alarms[i].enabled) {
                    return true
                }
            }
        }
        return false
    }
    
    property int brightness: Math.round(DisplayManager.brightness * 100)
    property int volume: Math.round(AudioManager.volume * 100)
    
    property bool isLowPowerMode: PowerManager.isPowerSaveMode
    
    function toggleWifi() {
        NetworkManager.toggleWifi()
        Logger.info("SystemControl", "WiFi toggled to: " + NetworkManager.wifiEnabled)
    }
    
    function toggleBluetooth() {
        NetworkManager.toggleBluetooth()
        Logger.info("SystemControl", "Bluetooth toggled to: " + NetworkManager.bluetoothEnabled)
    }
    
    function toggleAirplaneMode() {
        var newMode = !isAirplaneModeOn
        NetworkManager.setAirplaneMode(newMode)
        Logger.info("SystemControl", "Airplane mode toggled to: " + newMode)
    }
    
    function toggleRotationLock() {
        var newLock = !isRotationLocked
        DisplayManager.setRotationLock(newLock)
        isRotationLocked = newLock
        Logger.info("SystemControl", "Rotation lock: " + isRotationLocked)
    }
    
    function toggleFlashlight() {
        if (typeof FlashlightManager !== 'undefined') {
            FlashlightManager.toggle()
            isFlashlightOn = FlashlightManager.enabled
        }
        Logger.info("SystemControl", "Flashlight: " + isFlashlightOn)
    }
    
    function toggleCellular() {
        if (typeof CellularManager !== 'undefined') {
            CellularManager.toggleModem()
            isCellularOn = CellularManager.modemEnabled
        }
        Logger.info("SystemControl", "Cellular: " + isCellularOn)
    }
    
    function toggleCellularData() {
        if (typeof CellularManager !== 'undefined') {
            CellularManager.toggleData()
            isCellularDataOn = CellularManager.dataEnabled
        }
        Logger.info("SystemControl", "Cellular Data: " + isCellularDataOn)
    }
    
    function toggleDndMode() {
        var newMode = !isDndMode
        AudioManager.setDoNotDisturb(newMode)
        Logger.info("SystemControl", "DND mode toggled to: " + newMode)
    }
    
    function toggleAlarm() {
        Logger.info("SystemControl", "Alarm quick settings tapped - opening Clock app")
    }
    
    function toggleLowPowerMode() {
        var newMode = !isLowPowerMode
        PowerManager.setPowerSaveMode(newMode)
        Logger.info("SystemControl", "Low power mode toggled to: " + newMode)
    }
    
    function setBrightness(value) {
        var clamped = Math.max(0, Math.min(100, value))
        DisplayManager.setBrightness(clamped / 100.0)
        Logger.debug("SystemControl", "Brightness: " + clamped)
        // Don't set brightness property here - let the binding update from DisplayManager
    }
    
    function setVolume(value) {
        var clamped = Math.max(0, Math.min(100, value))
        AudioManager.setVolume(clamped / 100.0)
        Logger.debug("SystemControl", "Volume: " + clamped)
        // Don't set volume property here - let the binding update from AudioManager
    }
    
    function sleep() {
        Logger.info("SystemControl", "Sleep triggered")
        PowerManager.suspend()
    }
    
    function powerOff() {
        Logger.info("SystemControl", "Power off triggered")
        PowerManager.shutdown()
    }
    
    function reboot() {
        Logger.info("SystemControl", "Reboot triggered")
        PowerManager.restart()
    }
    
    // Bindings automatically update from NetworkManager properties (lines 8-10)
    // No need for Connections - the property bindings handle updates
    
    property Connections displayManagerConnections: Connections {
        target: DisplayManager
        function onBrightnessSet(value) {
            brightness = Math.round(value * 100)
        }
    }
    
    property Connections audioManagerConnections: Connections {
        target: AudioManager
        function onVolumeSet(value) {
            volume = Math.round(value * 100)
        }
    }
    
    // Binding automatically updates from PowerManager.isPowerSaveMode (line 32)
    
    Component.onCompleted: {
        console.log("[SystemControlStore] Initialized with real services")
    }
}
