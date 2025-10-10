pragma Singleton
import QtQuick

QtObject {
    id: systemControl
    
    // Settings state
    property bool isWifiOn: true
    property bool isBluetoothOn: false
    property bool isAirplaneModeOn: false
    property bool isRotationLocked: false
    property bool isFlashlightOn: false
    property bool isDndMode: false
    property bool isAlarmOn: true
    
    // Brightness & Volume
    property int brightness: 70
    property int volume: 50
    
    // Power
    property bool isLowPowerMode: false
    
    // Methods
    function toggleWifi() {
        isWifiOn = !isWifiOn
        console.log("WiFi toggled:", isWifiOn)
    }
    
    function toggleBluetooth() {
        isBluetoothOn = !isBluetoothOn
        console.log("Bluetooth toggled:", isBluetoothOn)
    }
    
    function toggleAirplaneMode() {
        isAirplaneModeOn = !isAirplaneModeOn
        if (isAirplaneModeOn) {
            isWifiOn = false
            isBluetoothOn = false
        }
        console.log("Airplane mode toggled:", isAirplaneModeOn)
    }
    
    function toggleRotationLock() {
        isRotationLocked = !isRotationLocked
        console.log("Rotation lock toggled:", isRotationLocked)
    }
    
    function toggleFlashlight() {
        isFlashlightOn = !isFlashlightOn
        console.log("Flashlight toggled:", isFlashlightOn)
    }
    
    function toggleDndMode() {
        isDndMode = !isDndMode
        console.log("DND mode toggled:", isDndMode)
    }
    
    function toggleAlarm() {
        isAlarmOn = !isAlarmOn
        console.log("Alarm toggled:", isAlarmOn)
    }
    
    function setBrightness(value) {
        brightness = Math.max(0, Math.min(100, value))
        console.log("Brightness set to:", brightness)
    }
    
    function setVolume(value) {
        volume = Math.max(0, Math.min(100, value))
        console.log("Volume set to:", volume)
    }
    
    function sleep() {
        console.log("Device sleep triggered")
    }
    
    function powerOff() {
        console.log("Device power off triggered")
    }
    
    function reboot() {
        console.log("Device reboot triggered")
    }
}

