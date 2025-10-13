pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: systemControl
    
    property bool isWifiOn: NetworkManager.wifiEnabled
    property bool isBluetoothOn: NetworkManager.bluetoothEnabled
    property bool isAirplaneModeOn: NetworkManager.airplaneModeEnabled
    property bool isRotationLocked: DisplayManager.rotationLocked
    property bool isFlashlightOn: false
    property bool isDndMode: AudioManager.dndEnabled
    property bool isAlarmOn: true
    
    property int brightness: Math.round(DisplayManager.brightness * 100)
    property int volume: Math.round(AudioManager.volume * 100)
    
    property bool isLowPowerMode: PowerManager.isPowerSaveMode
    
    function toggleWifi() {
        NetworkManager.toggleWifi()
        isWifiOn = NetworkManager.wifiEnabled
        Logger.info("SystemControl", "WiFi: " + isWifiOn)
    }
    
    function toggleBluetooth() {
        NetworkManager.toggleBluetooth()
        isBluetoothOn = NetworkManager.bluetoothEnabled
        Logger.info("SystemControl", "Bluetooth: " + isBluetoothOn)
    }
    
    function toggleAirplaneMode() {
        var newMode = !isAirplaneModeOn
        NetworkManager.setAirplaneMode(newMode)
        isAirplaneModeOn = newMode
        isWifiOn = NetworkManager.wifiEnabled
        isBluetoothOn = NetworkManager.bluetoothEnabled
        Logger.info("SystemControl", "Airplane mode: " + isAirplaneModeOn)
    }
    
    function toggleRotationLock() {
        var newLock = !isRotationLocked
        DisplayManager.setRotationLock(newLock)
        isRotationLocked = newLock
        Logger.info("SystemControl", "Rotation lock: " + isRotationLocked)
    }
    
    function toggleFlashlight() {
        isFlashlightOn = !isFlashlightOn
        Logger.info("SystemControl", "Flashlight: " + isFlashlightOn)
    }
    
    function toggleDndMode() {
        var newMode = !isDndMode
        AudioManager.setDoNotDisturb(newMode)
        isDndMode = newMode
        Logger.info("SystemControl", "DND mode: " + isDndMode)
    }
    
    function toggleAlarm() {
        isAlarmOn = !isAlarmOn
        Logger.info("SystemControl", "Alarm: " + isAlarmOn)
    }
    
    function setBrightness(value) {
        brightness = Math.max(0, Math.min(100, value))
        DisplayManager.setBrightness(brightness / 100.0)
        Logger.debug("SystemControl", "Brightness: " + brightness)
    }
    
    function setVolume(value) {
        volume = Math.max(0, Math.min(100, value))
        AudioManager.setVolume(volume / 100.0)
        Logger.debug("SystemControl", "Volume: " + volume)
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
    
    property Connections networkManagerConnections: Connections {
        target: NetworkManager
        function onWifiEnabledChanged() {
            isWifiOn = NetworkManager.wifiEnabled
        }
        function onBluetoothEnabledChanged() {
            isBluetoothOn = NetworkManager.bluetoothEnabled
        }
        function onAirplaneModeEnabledChanged() {
            isAirplaneModeOn = NetworkManager.airplaneModeEnabled
        }
    }
    
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
    
    property Connections powerManagerConnections: Connections {
        target: PowerManager
        function onIsPowerSaveModeChanged() {
            isLowPowerMode = PowerManager.isPowerSaveMode
        }
    }
    
    Component.onCompleted: {
        console.log("[SystemControlStore] Initialized with real services")
    }
}
