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
    readonly property bool isLocationOn: SettingsManagerCpp.locationEnabled
    readonly property bool isHotspotOn: Network.hotspotActive
    readonly property string hotspotSsid: Network.hotspotSsid
    readonly property string hotspotPassword: Network.hotspotPassword
    readonly property bool isVibrationOn: HapticManager.enabled
    readonly property bool isNightLightOn: Display.nightLightEnabled
    readonly property bool isLowPowerMode: Power.isPowerSaveMode
    readonly property int brightness: Math.round(Math.min(Math.max(Display.brightness, 0), 1) * 100)
    readonly property int volume: Math.round(Math.min(Math.max(AudioManagerCpp.volume, 0), 1) * 100)

    // Switches toggled whose backend has not reached the new state yet, for
    // 10 s at most. Tiles show the new state at once (shown()); one that
    // times out goes back and says so (switchFailed).
    property var pendingSwitches: []
    property var pendingUntil: ({})
    property var pendingTarget: ({})

    signal userBrightnessChanged(int value)
    signal hotspotFailed(string message)
    signal switchFailed(string id, bool target)

    // A pending switch takes no second tap: its backends only toggle, and a
    // second request would race the first.
    function markPending(id, target) {
        pendingUntil[id] = Date.now() + 10000;
        pendingTarget[id] = target;
        if (pendingSwitches.indexOf(id) < 0)
            pendingSwitches = pendingSwitches.concat([id]);
        expiry.start();
    }

    function clearPending(id) {
        delete pendingUntil[id];
        delete pendingTarget[id];
        if (pendingSwitches.indexOf(id) >= 0)
            pendingSwitches = pendingSwitches.filter(s => s !== id);
    }

    // What a switch shows: the state asked for while it is pending.
    function shown(id, actual) {
        return pendingSwitches.indexOf(id) >= 0 ? pendingTarget[id] === true : actual;
    }

    function settle(id, actual) {
        if (pendingSwitches.indexOf(id) >= 0 && pendingTarget[id] === actual)
            clearPending(id);
    }

    onIsWifiOnChanged: settle("wifi", isWifiOn)
    onIsBluetoothOnChanged: settle("bluetooth", isBluetoothOn)
    onIsCellularDataOnChanged: settle("cellular", isCellularDataOn)
    onIsHotspotOnChanged: settle("hotspot", isHotspotOn)
    onIsAirplaneModeOnChanged: settle("airplane", isAirplaneModeOn)

    readonly property Timer expiry: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const id of root.pendingSwitches.slice()) {
                if (!(root.pendingUntil[id] > now)) {
                    const target = root.pendingTarget[id] === true;
                    root.clearPending(id);
                    root.switchFailed(id, target);
                }
            }
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
        if (pendingSwitches.indexOf("wifi") >= 0)
            return;
        markPending("wifi", !isWifiOn);
        Network.toggleWifi();
    }

    function toggleBluetooth() {
        if (pendingSwitches.indexOf("bluetooth") >= 0)
            return;
        markPending("bluetooth", !isBluetoothOn);
        BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled;
    }

    function toggleAirplaneMode() {
        if (pendingSwitches.indexOf("airplane") >= 0)
            return;
        markPending("airplane", !isAirplaneModeOn);
        Network.setAirplaneMode(!isAirplaneModeOn);
    }

    function toggleRotationLock() {
        Display.rotationLocked = !isRotationLocked;
    }

    function toggleFlashlight() {
        FlashlightManagerCpp.toggle();
    }

    function toggleCellularData() {
        if (pendingSwitches.indexOf("cellular") >= 0)
            return;
        markPending("cellular", !isCellularDataOn);
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
        SettingsManagerCpp.locationEnabled = !isLocationOn;
    }

    function toggleHotspot() {
        if (pendingSwitches.indexOf("hotspot") >= 0)
            return;
        markPending("hotspot", !isHotspotOn);
        Network.toggleHotspot();
    }

    function ensureHotspotCredentials() {
        Network.ensureHotspotCredentials();
    }

    function toggleVibration() {
        SettingsManagerCpp.vibrationEnabled = !SettingsManagerCpp.vibrationEnabled;
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
