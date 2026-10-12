pragma Singleton
import QtQml

// Mirrors src/SettingsController's dialog state and text helpers.
QtObject {
    property var notificationApps: [{ id: "notes", name: "Notes", enabled: true }, { id: "weather", name: "Weather", enabled: false }]
    property string osVersion: "postmarketOS edge"
    property string kernelVersion: "linux 6.12"
    property string deviceModel: "Purism Librem 5"
    property string displayResolution: "720x1440"
    property string displayRefreshRate: "60 Hz"
    property string displayDpi: "268.0"
    property string displayScale: "2.00"
    property var openSourceLicenses: [{ title: "Marathon OS", items: [{ title: "Marathon Shell", subtitle: "Core shell and system apps", value: "Apache-2.0" }] }]

    property bool wifiDialogVisible: false
    property string wifiDialogSsid: ""
    property int wifiDialogStrength: 0
    property string wifiDialogSecurity: ""
    property bool wifiDialogSecured: true
    property bool wifiDialogConnecting: false
    property string wifiDialogError: ""

    property bool bluetoothDialogVisible: false
    property string bluetoothDialogName: ""
    property string bluetoothDialogAddress: ""
    property string bluetoothDialogType: ""
    property string bluetoothDialogMode: ""
    property string bluetoothDialogPasskey: ""
    property bool bluetoothDialogPairing: false
    property string bluetoothDialogError: ""

    property var calls: []

    function reset() {
        wifiDialogVisible = false;
        wifiDialogConnecting = false;
        wifiDialogError = "";
        bluetoothDialogVisible = false;
        bluetoothDialogPairing = false;
        bluetoothDialogError = "";
        calls = [];
    }
    function record(call) {
        calls = calls.concat([call]);
    }

    function showWifiDialog(ssid, strength, security, secured) {
        wifiDialogSsid = ssid;
        wifiDialogStrength = strength;
        wifiDialogSecurity = security === "" ? "WPA2" : security;
        wifiDialogSecured = secured;
        wifiDialogConnecting = false;
        wifiDialogError = "";
        wifiDialogVisible = true;
    }
    function dismissWifiDialog() {
        wifiDialogVisible = false;
    }
    function submitWifiPassword(password) {
        record(["wifiPassword", wifiDialogSsid, password]);
        wifiDialogError = "";
        wifiDialogConnecting = true;
    }
    // Test hooks for the network manager's answers.
    function wifiSucceeded() {
        wifiDialogConnecting = false;
        wifiDialogVisible = false;
    }
    function wifiFailed(message) {
        wifiDialogConnecting = false;
        wifiDialogError = message;
    }

    function showBluetoothDialog(name, address, type, mode) {
        bluetoothDialogName = name;
        bluetoothDialogAddress = address;
        bluetoothDialogType = type === "" ? "device" : type;
        bluetoothDialogMode = mode === "" ? "justworks" : mode;
        bluetoothDialogPasskey = "";
        bluetoothDialogPairing = false;
        bluetoothDialogError = "";
        bluetoothDialogVisible = true;
    }
    function showBluetoothPasskeyConfirmation(name, address, type, passkey) {
        showBluetoothDialog(name, address, type, "confirm");
        bluetoothDialogPasskey = String(passkey);
    }
    function dismissBluetoothDialog() {
        bluetoothDialogVisible = false;
    }
    function submitBluetoothPin(pin) {
        record(["pin", bluetoothDialogAddress, pin]);
        bluetoothDialogPairing = true;
    }
    function submitBluetoothPasskey(passkey) {
        record(["passkey", bluetoothDialogAddress, passkey]);
        bluetoothDialogPairing = true;
    }
    function confirmBluetoothPairing(accepted) {
        record(["confirm", bluetoothDialogAddress, accepted]);
        if (accepted)
            bluetoothDialogPairing = true;
        else
            dismissBluetoothDialog();
    }
    function cancelBluetoothPairing() {
        record(["cancel", bluetoothDialogAddress]);
        dismissBluetoothDialog();
    }
    function bluetoothSucceeded() {
        bluetoothDialogPairing = false;
        bluetoothDialogVisible = false;
    }
    function bluetoothFailed(message) {
        bluetoothDialogPairing = false;
        bluetoothDialogError = message;
    }
    function bluetoothPairingModeText(mode) {
        return { pin: "Enter PIN to pair", passkey: "Enter passkey displayed on device", confirm: "Confirm pairing code" }[mode] || "Ready to pair";
    }
    function bluetoothHelpText(mode) {
        return { pin: "Enter the PIN shown on your device (usually 0000 or 1234)", passkey: "Type the 6-digit passkey displayed on the device", confirm: "Make sure the code above matches what's shown on your device" }[mode] || "No PIN required for this device";
    }
    function bluetoothCanPair(mode, pin, passkey) {
        if (mode === "confirm" || mode === "justworks")
            return true;
        if (mode === "pin")
            return pin.length >= 4;
        return mode === "passkey" && passkey.length === 6;
    }

    function batteryStatusText(charging, plugged, seconds) {
        if (charging)
            return "Charging";
        if (plugged)
            return "Plugged In, Not Charging";
        return seconds > 0 ? Math.floor(seconds / 3600) + "h remaining" : "Discharging";
    }
    function wifiConnectionStatusText(strength) {
        return "Connected • " + strength + "% signal";
    }
    function availableNetworkSubtitle(security, strength, frequency) {
        return (security === "" ? "Open" : security) + " • " + strength + "% signal";
    }
    function lockoutStatusText(locked, seconds) {
        return locked ? "Locked (" + seconds + "s remaining)" : "Active";
    }
    function quickPinValidationError(pin, password) {
        if (pin.length < 4)
            return "PIN must be 4-6 digits";
        if (password.trim() === "")
            return "System password required";
        return "";
    }
    function soundTypeLabel(type) {
        return { ringtone: "Ringtone", notification: "Notification Sound", alarm: "Alarm Sound" }[type] || "Sound";
    }

    function setNotificationEnabled(appId, enabled) {
        record(["notify", appId, enabled]);
        notificationApps = notificationApps.map(a => a.id === appId ? Object.assign({}, a, { enabled: enabled }) : a);
    }
}
