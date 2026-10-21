pragma Singleton
import QtQuick
import MarathonOS.Shell

// Quick Settings' switches and sliders, over the shell's system objects.
QtObject {
    id: root

    readonly property bool isWifiOn: Network.wifiEnabled
    readonly property bool isBluetoothOn: BluetoothManagerCpp.enabled
    readonly property bool isAirplaneModeOn: Network.airplaneModeEnabled
    readonly property bool isRotationLocked: Display.rotationLocked
    readonly property bool isFlashlightOn: FlashlightManagerCpp.enabled
    readonly property bool isCellularDataOn: Modem.dataEnabled
    readonly property bool isDndMode: SettingsManagerCpp.dndEnabled
    readonly property bool isAutoBrightnessOn: Display.autoBrightness
    readonly property bool isLocationOn: LocationManager.active
    readonly property bool isHotspotOn: Network.hotspotActive
    readonly property string hotspotSsid: Network.hotspotSsid
    readonly property string hotspotPassword: Network.hotspotPassword
    readonly property bool isVibrationOn: HapticManager.enabled
    readonly property bool isNightLightOn: Display.nightLightEnabled
    readonly property bool isLowPowerMode: Power.isPowerSaveMode
    readonly property int brightness: Math.round(Math.min(Math.max(Display.brightness, 0), 1) * 100)
    readonly property int volume: Math.round(Math.min(Math.max(AudioManagerCpp.volume, 0), 1) * 100)

    // Switches toggled whose backend has not answered yet, for 10 s at most.
    property var pendingSwitches: []
    property var pendingUntil: ({})

    signal userBrightnessChanged(int value)
    signal hotspotFailed(string message)

    function markPending(id) {
        pendingUntil[id] = Date.now() + 10000;
        if (pendingSwitches.indexOf(id) < 0)
            pendingSwitches = pendingSwitches.concat([id]);
        expiry.start();
    }

    function clearPending(id) {
        delete pendingUntil[id];
        if (pendingSwitches.indexOf(id) >= 0)
            pendingSwitches = pendingSwitches.filter(s => s !== id);
    }

    onIsWifiOnChanged: clearPending("wifi")
    onIsBluetoothOnChanged: clearPending("bluetooth")
    onIsCellularDataOnChanged: clearPending("cellular")
    onIsLocationOnChanged: clearPending("location")
    onIsHotspotOnChanged: clearPending("hotspot")

    readonly property Timer expiry: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const id of root.pendingSwitches.slice())
                if (!(root.pendingUntil[id] > now))
                    root.clearPending(id);
            if (root.pendingSwitches.length === 0)
                stop();
        }
    }

    readonly property Connections hotspot: Connections {
        function onHotspotFailed(message) {
            root.clearPending("hotspot");
            root.hotspotFailed(message);
        }

        target: Network
    }

    function toggleWifi() {
        markPending("wifi");
        Network.toggleWifi();
    }

    function toggleBluetooth() {
        markPending("bluetooth");
        BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled;
    }

    function toggleAirplaneMode() {
        Network.setAirplaneMode(!isAirplaneModeOn);
    }

    function toggleRotationLock() {
        Display.rotationLocked = !isRotationLocked;
    }

    function toggleFlashlight() {
        FlashlightManagerCpp.toggle();
    }

    function toggleCellularData() {
        markPending("cellular");
        if (Modem.dataEnabled)
            Modem.disableData();
        else
            Modem.enableData();
    }

    function toggleDndMode() {
        SettingsManagerCpp.dndEnabled = !isDndMode;
    }

    function toggleLowPowerMode() {
        Power.setPowerSaveMode(!isLowPowerMode);
    }

    function toggleAutoBrightness() {
        Display.autoBrightness = !isAutoBrightnessOn;
    }

    function toggleLocation() {
        markPending("location");
        if (isLocationOn)
            LocationManager.stop();
        else
            LocationManager.start();
    }

    function toggleHotspot() {
        markPending("hotspot");
        Network.toggleHotspot();
    }

    function ensureHotspotCredentials() {
        Network.ensureHotspotCredentials();
    }

    function toggleVibration() {
        HapticManager.enabled = !isVibrationOn;
    }

    function toggleNightLight() {
        Display.nightLightEnabled = !isNightLightOn;
    }

    function captureScreenshot() {
        ScreenshotService.captureScreen();
    }

    function setBrightness(value) {
        Display.setBrightness(Math.min(Math.max(value, 0), 100) / 100);
    }

    // Teaches the adaptive curve, and shows the HUD.
    function setBrightnessFromUser(value) {
        const v = Math.min(Math.max(value, 0), 100);
        Display.setBrightnessFromUser(v / 100);
        userBrightnessChanged(v);
    }

    function setVolume(value) {
        AudioManagerCpp.setVolume(Math.min(Math.max(value, 0), 100) / 100);
    }
}
