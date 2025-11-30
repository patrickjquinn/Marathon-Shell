pragma Singleton
import QtQuick

Item {
    id: networkManager

    property bool wifiEnabled: NetworkManagerCpp ? NetworkManagerCpp.wifiEnabled : true
    property bool wifiConnected: NetworkManagerCpp ? NetworkManagerCpp.wifiConnected : true
    property string wifiSsid: NetworkManagerCpp ? NetworkManagerCpp.wifiSsid : "Home Network"
    property int wifiSignalStrength: NetworkManagerCpp ? NetworkManagerCpp.wifiSignalStrength : 85
    property bool ethernetConnected: NetworkManagerCpp ? NetworkManagerCpp.ethernetConnected : false
    property string ethernetConnectionName: NetworkManagerCpp ? NetworkManagerCpp.ethernetConnectionName : ""
    property bool wifiAvailable: NetworkManagerCpp ? NetworkManagerCpp.wifiAvailable : false
    property bool bluetoothAvailable: BluetoothManagerCpp ? BluetoothManagerCpp.available : false
    property string wifiSecurity: "WPA2"
    property string wifiIpAddress: "192.168.1.100"

    property bool cellularEnabled: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.modemEnabled : false
    property bool cellularConnected: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.registered : false
    property string cellularOperator: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.operatorName : ""
    property string cellularTechnology: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.networkType : "Unknown"
    property int cellularSignalStrength: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.signalStrength : 0
    property bool cellularRoaming: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.roaming : false
    property bool cellularDataEnabled: typeof ModemManagerCpp !== 'undefined' ? ModemManagerCpp.dataEnabled : false

    property bool bluetoothEnabled: BluetoothManagerCpp ? BluetoothManagerCpp.enabled : false
    property int bluetoothConnectedDevices: 0 // TODO: Calculate from BluetoothManagerCpp devices

    property bool airplaneModeEnabled: NetworkManagerCpp ? NetworkManagerCpp.airplaneModeEnabled : false
    property bool vpnConnected: false
    property string vpnName: ""

    readonly property bool isOnline: wifiConnected || cellularConnected
    readonly property bool hasInternet: isOnline && !airplaneModeEnabled

    property var availableWifiNetworks: NetworkManagerCpp ? NetworkManagerCpp.availableNetworks : []
    property var pairedBluetoothDevices: BluetoothManagerCpp ? BluetoothManagerCpp.pairedDevices : []

    property bool isScanning: false
    property alias availableNetworks: networkManager.availableWifiNetworks

    signal networkListUpdated
    signal connectionError(string error)
    signal connectionSuccess
    signal connectionFailed(string message)

    // Forward signals from C++ backend
    Connections {
        target: NetworkManagerCpp

        function onAvailableNetworksChanged() {
            networkListUpdated();
        }

        function onConnectionSuccess() {
            connectionSuccess();
        }

        function onConnectionFailed(message) {
            connectionFailed(message);
        }

        function onNetworkError(message) {
            connectionError(message);
        }
    }

    function enableWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.enableWifi();
        }
    }

    function disableWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.disableWifi();
        }
    }

    function toggleWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.toggleWifi();
        }
    }

    function scanWifi() {
        console.log("[NetworkManager] Scanning for WiFi networks...");
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.scanWifi();
        }
    }

    function scanWifiNetworks() {
        scanWifi();
    }

    function connectToWifi(ssid, password) {
        console.log("[NetworkManager] Connecting to:", ssid);
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.connectToNetwork(ssid, password);
        }
    }

    function disconnectWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.disconnectWifi();
        }
    }

    function enableCellular() {
        console.log("[NetworkManager] Enabling cellular...");
        cellularEnabled = true;
    }

    function disableCellular() {
        console.log("[NetworkManager] Disabling cellular...");
        cellularEnabled = false;
        cellularConnected = false;
    }

    function enableBluetooth() {
        if (typeof BluetoothManagerCpp !== 'undefined') {
            BluetoothManagerCpp.enabled = true;
        }
    }

    function disableBluetooth() {
        if (typeof BluetoothManagerCpp !== 'undefined') {
            BluetoothManagerCpp.enabled = false;
        }
    }

    function toggleBluetooth() {
        if (typeof BluetoothManagerCpp !== 'undefined') {
            BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled;
        }
    }

    function setAirplaneMode(enabled) {
        console.log("[NetworkManager] Airplane mode:", enabled);
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.setAirplaneMode(enabled);
        }
    }

    function toggleAirplaneMode() {
        setAirplaneMode(!airplaneModeEnabled);
    }

    function enableCellularData() {
        console.log("[NetworkManager] Enabling cellular data...");
        cellularDataEnabled = true;
    }

    function disableCellularData() {
        console.log("[NetworkManager] Disabling cellular data...");
        cellularDataEnabled = false;
    }

    Component.onCompleted: {
        console.log("[NetworkManager] Initialized (proxying to C++ backend)");
        if (typeof NetworkManagerCpp !== 'undefined') {
            console.log("[NetworkManager] C++ backend available");
        } else {
            console.log("[NetworkManager] C++ backend not available, using mock data");
        }
    }
}
