pragma Singleton
import QtQml

QtObject {
    property bool enabled: false
    property bool scanning: false
    property var devices: []
    property var pairedDevices: []
    property var calls: []

    function reset() {
        enabled = false;
        scanning = false;
        devices = [];
        pairedDevices = [];
        calls = [];
    }
    function record(call) {
        calls = calls.concat([call]);
    }
    function startScan() {
        record(["startScan"]);
        scanning = true;
    }
    function stopScan() {
        record(["stopScan"]);
        scanning = false;
    }
    function connectDevice(address) {
        record(["connect", address]);
    }
    function disconnectDevice(address) {
        record(["disconnect", address]);
    }
    function unpairDevice(address) {
        record(["unpair", address]);
        pairedDevices = pairedDevices.filter(d => d.address !== address);
    }
}
