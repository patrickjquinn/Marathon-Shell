pragma Singleton
import QtQuick

QtObject {
    // Don't set brightness property here - let the binding update from DisplayManager
    // Don't set volume property here - let the binding update from AudioManager
    // Bindings automatically update from NetworkManagerCpp/BluetoothManagerCpp properties and Binding objects above
    // No need for Connections - the Binding objects with restoreMode handle everything
    // Binding automatically updates from PowerManager.isPowerSaveMode (line 32)
    // Don't assign - let the binding update automatically
    // Don't assign - let the binding update automatically
    // Don't assign - let the binding update automatically
    // Default hotspot config - can be customized later

    id: systemControl

    property bool isWifiOn: typeof NetworkManagerCpp !== 'undefined' && NetworkManagerCpp ? NetworkManagerCpp.wifiEnabled : true
    property bool isBluetoothOn: typeof BluetoothManagerCpp !== 'undefined' && BluetoothManagerCpp ? BluetoothManagerCpp.enabled : false
    property bool isAirplaneModeOn: typeof NetworkManagerCpp !== 'undefined' && NetworkManagerCpp ? NetworkManagerCpp.airplaneModeEnabled : false
    property bool isRotationLocked: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.rotationLocked : false
    property bool isFlashlightOn: (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp) ? FlashlightManagerCpp.enabled : false
    property bool isCellularOn: typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp ? ModemManagerCpp.modemEnabled : false
    property bool isCellularDataOn: typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp ? ModemManagerCpp.dataEnabled : false
    property bool isDndMode: AudioManager.dndEnabled
    property bool isAlarmOn: typeof AlarmManager !== 'undefined' ? (AlarmManager.hasActiveAlarm || _hasEnabledAlarm()) : false
    property bool isAutoBrightnessOn: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.autoBrightnessEnabled : false
    property bool isLocationOn: typeof LocationManager !== 'undefined' ? LocationManager.active : false
    property bool isHotspotOn: typeof NetworkManagerCpp !== 'undefined' ? NetworkManagerCpp.isHotspotActive() : false
    property bool isVibrationOn: typeof HapticManager !== 'undefined' ? HapticManager.enabled : true
    property bool isNightLightOn: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.nightLightEnabled : false
    property int brightness: 50 // Managed by binding below
    property int volume: 50 // Managed by binding below
    // Two-way bindings with restore mode (as properties)
    property Binding brightnessBinding
    property Binding volumeBinding
    property bool isLowPowerMode: (typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.isPowerSaveMode : false
    // Two-way binding for rotation lock (as property)
    property Binding rotationLockBinding

    function _hasEnabledAlarm() {
        if (typeof AlarmManager !== 'undefined' && AlarmManager.alarms) {
            for (var i = 0; i < AlarmManager.alarms.length; i++) {
                if (AlarmManager.alarms[i].enabled)
                    return true;
            }
        }
        return false;
    }

    function toggleWifi() {
        if (typeof NetworkManagerCpp !== 'undefined' && NetworkManagerCpp)
            NetworkManagerCpp.toggleWifi();

        Logger.info("SystemControl", "WiFi toggled to: " + (typeof NetworkManagerCpp !== 'undefined' && NetworkManagerCpp ? NetworkManagerCpp.wifiEnabled : "unknown"));
    }

    function toggleBluetooth() {
        if (typeof BluetoothManagerCpp !== 'undefined' && BluetoothManagerCpp)
            BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled;

        Logger.info("SystemControl", "Bluetooth toggled to: " + (typeof BluetoothManagerCpp !== 'undefined' && BluetoothManagerCpp ? BluetoothManagerCpp.enabled : "unknown"));
    }

    function toggleAirplaneMode() {
        var newMode = !isAirplaneModeOn;
        if (typeof NetworkManagerCpp !== 'undefined' && NetworkManagerCpp)
            NetworkManagerCpp.setAirplaneMode(newMode);

        Logger.info("SystemControl", "Airplane mode toggled to: " + newMode);
    }

    function toggleRotationLock() {
        var newLock = !isRotationLocked;
        if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.rotationLocked = newLock;

        Logger.info("SystemControl", "Rotation lock: " + newLock);
    }

    function toggleFlashlight() {
        if (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp)
            FlashlightManagerCpp.toggle();

        Logger.info("SystemControl", "Flashlight: " + isFlashlightOn);
    }

    function toggleCellular() {
        if (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp) {
            if (ModemManagerCpp.modemEnabled)
                ModemManagerCpp.disable();
            else
                ModemManagerCpp.enable();
        }
        Logger.info("SystemControl", "Cellular: " + isCellularOn);
    }

    function toggleCellularData() {
        if (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp) {
            if (ModemManagerCpp.dataEnabled)
                ModemManagerCpp.disableData();
            else
                ModemManagerCpp.enableData();
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
        if (typeof PowerManagerService !== "undefined" && PowerManagerService)
            PowerManagerService.setPowerSaveMode(newMode);

        Logger.info("SystemControl", "Low power mode toggled to: " + newMode);
    }

    function toggleAutoBrightness() {
        var newMode = !isAutoBrightnessOn;
        if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.autoBrightnessEnabled = newMode;

        Logger.info("SystemControl", "Auto-brightness toggled to: " + newMode);
    }

    function toggleLocation() {
        if (typeof LocationManager !== 'undefined') {
            if (isLocationOn)
                LocationManager.stop();
            else
                LocationManager.start();
            Logger.info("SystemControl", "Location toggled to: " + !isLocationOn);
        }
    }

    function toggleHotspot() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            if (isHotspotOn)
                NetworkManagerCpp.stopHotspot();
            else
                NetworkManagerCpp.createHotspot("Marathon Hotspot", "marathon2025");
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
        if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.nightLightEnabled = newMode;

        Logger.info("SystemControl", "Night Light toggled to: " + newMode);
    }

    function captureScreenshot() {
        Logger.info("SystemControl", "Screenshot captured");
        // Screenshot logic will be handled by ScreenshotService
        if (typeof ScreenshotService !== 'undefined')
            ScreenshotService.captureScreen();
    }

    function setBrightness(value) {
        var clamped = Math.max(0, Math.min(100, value));
        if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
            DisplayManagerCpp.brightness = clamped / 100;

        Logger.debug("SystemControl", "Brightness: " + clamped);
    }

    function setVolume(value) {
        var clamped = Math.max(0, Math.min(100, value));
        AudioManager.setVolume(clamped / 100);
        Logger.debug("SystemControl", "Volume: " + clamped);
    }

    function sleep() {
        Logger.info("SystemControl", "Sleep triggered");
        if (typeof PowerManagerService !== "undefined" && PowerManagerService)
            PowerManagerService.suspend();
    }

    function powerOff() {
        Logger.info("SystemControl", "Power off triggered");
        if (typeof PowerManagerService !== "undefined" && PowerManagerService)
            PowerManagerService.shutdown();
    }

    function reboot() {
        Logger.info("SystemControl", "Reboot triggered");
        if (typeof PowerManagerService !== "undefined" && PowerManagerService)
            PowerManagerService.restart();
    }

    Component.onCompleted: {
        console.log("[SystemControlStore] Initialized with real services");
    }

    brightnessBinding: Binding {
        target: systemControl
        property: "brightness"
        value: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? Math.round(DisplayManagerCpp.brightness * 100) : 50
        restoreMode: Binding.RestoreBinding
    }

    volumeBinding: Binding {
        target: systemControl
        property: "volume"
        value: Math.round(AudioManager.volume * 100)
        restoreMode: Binding.RestoreBinding
    }

    rotationLockBinding: Binding {
        target: systemControl
        property: "isRotationLocked"
        value: (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp) ? DisplayManagerCpp.rotationLocked : false
        restoreMode: Binding.RestoreBinding
    }
}
