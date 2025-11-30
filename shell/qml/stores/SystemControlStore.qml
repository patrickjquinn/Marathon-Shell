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
    property bool isAutoBrightnessOn: DisplayManagerCpp.autoBrightnessEnabled
    property bool isLocationOn: typeof LocationManager !== 'undefined' ? LocationManager.active : false
    property bool isHotspotOn: typeof NetworkManagerCpp !== 'undefined' ? NetworkManagerCpp.isHotspotActive() : false
    property bool isVibrationOn: typeof HapticManager !== 'undefined' ? HapticManager.enabled : true
    property bool isNightLightOn: DisplayManagerCpp.nightLightEnabled

    function _hasEnabledAlarm() {
        if (typeof AlarmManager !== 'undefined' && AlarmManager.alarms) {
            for (var i = 0; i < AlarmManager.alarms.length; i++) {
                if (AlarmManager.alarms[i].enabled) {
                    return true;
                }
            }
        }
        return false;
    }

    property int brightness: 50  // Managed by binding below
    property int volume: 50  // Managed by binding below

    // Two-way bindings with restore mode (as properties)
    property Binding brightnessBinding: Binding {
        target: systemControl
        property: "brightness"
        value: Math.round(DisplayManager.brightness * 100)
        restoreMode: Binding.RestoreBinding
    }

    property Binding volumeBinding: Binding {
        target: systemControl
        property: "volume"
        value: Math.round(AudioManager.volume * 100)
        restoreMode: Binding.RestoreBinding
    }

    property bool isLowPowerMode: PowerManager.isPowerSaveMode

    function toggleWifi() {
        NetworkManager.toggleWifi();
        Logger.info("SystemControl", "WiFi toggled to: " + NetworkManager.wifiEnabled);
    }

    function toggleBluetooth() {
        NetworkManager.toggleBluetooth();
        Logger.info("SystemControl", "Bluetooth toggled to: " + NetworkManager.bluetoothEnabled);
    }

    function toggleAirplaneMode() {
        var newMode = !isAirplaneModeOn;
        NetworkManager.setAirplaneMode(newMode);
        Logger.info("SystemControl", "Airplane mode toggled to: " + newMode);
    }

    // Two-way binding for rotation lock (as property)
    property Binding rotationLockBinding: Binding {
        target: systemControl
        property: "isRotationLocked"
        value: DisplayManager.rotationLocked
        restoreMode: Binding.RestoreBinding
    }

    function toggleRotationLock() {
        var newLock = !isRotationLocked;
        DisplayManager.setRotationLock(newLock);
        Logger.info("SystemControl", "Rotation lock: " + newLock);
    }

    function toggleFlashlight() {
        if (typeof FlashlightManager !== 'undefined') {
            FlashlightManager.toggle();
            // Don't assign - let the binding update automatically
        }
        Logger.info("SystemControl", "Flashlight: " + isFlashlightOn);
    }

    function toggleCellular() {
        if (typeof CellularManager !== 'undefined') {
            CellularManager.toggleModem();
            // Don't assign - let the binding update automatically
        }
        Logger.info("SystemControl", "Cellular: " + isCellularOn);
    }

    function toggleCellularData() {
        if (typeof CellularManager !== 'undefined') {
            CellularManager.toggleData();
            // Don't assign - let the binding update automatically
        }
        Logger.info("SystemControl", "Cellular Data: " + isCellularDataOn);
    }

    function toggleDndMode() {
        var newMode = !isDndMode;
        AudioManager.setDoNotDisturb(newMode);
        Logger.info("SystemControl", "DND mode toggled to: " + newMode);
    }

    function toggleAlarm() {
        Logger.info("SystemControl", "Alarm quick settings tapped - opening Clock app");
    }

    function toggleLowPowerMode() {
        var newMode = !isLowPowerMode;
        PowerManager.setPowerSaveMode(newMode);
        Logger.info("SystemControl", "Low power mode toggled to: " + newMode);
    }

    function toggleAutoBrightness() {
        var newMode = !isAutoBrightnessOn;
        DisplayManagerCpp.setAutoBrightness(newMode);
        Logger.info("SystemControl", "Auto-brightness toggled to: " + newMode);
    }

    function toggleLocation() {
        if (typeof LocationManager !== 'undefined') {
            if (isLocationOn) {
                LocationManager.stop();
            } else {
                LocationManager.start();
            }
            Logger.info("SystemControl", "Location toggled to: " + !isLocationOn);
        }
    }

    function toggleHotspot() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            if (isHotspotOn) {
                NetworkManagerCpp.stopHotspot();
            } else {
                // Default hotspot config - can be customized later
                NetworkManagerCpp.createHotspot("Marathon Hotspot", "marathon2025");
            }
            Logger.info("SystemControl", "Hotspot toggled");
        }
    }

    function toggleVibration() {
        if (typeof HapticManager !== 'undefined') {
            var newMode = !isVibrationOn;
            HapticManager.setEnabled(newMode);
            Logger.info("SystemControl", "Vibration toggled to: " + newMode);
        }
    }

    function toggleNightLight() {
        var newMode = !isNightLightOn;
        DisplayManagerCpp.setNightLightEnabled(newMode);
        Logger.info("SystemControl", "Night Light toggled to: " + newMode);
    }

    function captureScreenshot() {
        Logger.info("SystemControl", "Screenshot captured");
        // Screenshot logic will be handled by ScreenshotService
        if (typeof ScreenshotService !== 'undefined') {
            ScreenshotService.captureScreen();
        }
    }

    function setBrightness(value) {
        var clamped = Math.max(0, Math.min(100, value));
        DisplayManager.setBrightness(clamped / 100.0);
        Logger.debug("SystemControl", "Brightness: " + clamped);
    // Don't set brightness property here - let the binding update from DisplayManager
    }

    function setVolume(value) {
        var clamped = Math.max(0, Math.min(100, value));
        AudioManager.setVolume(clamped / 100.0);
        Logger.debug("SystemControl", "Volume: " + clamped);
    // Don't set volume property here - let the binding update from AudioManager
    }

    function sleep() {
        Logger.info("SystemControl", "Sleep triggered");
        PowerManager.suspend();
    }

    function powerOff() {
        Logger.info("SystemControl", "Power off triggered");
        PowerManager.shutdown();
    }

    function reboot() {
        Logger.info("SystemControl", "Reboot triggered");
        PowerManager.restart();
    }

    // Bindings automatically update from NetworkManager properties and Binding objects above
    // No need for Connections - the Binding objects with restoreMode handle everything

    // Binding automatically updates from PowerManager.isPowerSaveMode (line 32)

    Component.onCompleted: {
        console.log("[SystemControlStore] Initialized with real services");
    }
}
