pragma Singleton
import QtQuick

QtObject {
    id: networkManager
    
    property bool wifiEnabled: NetworkManagerCpp ? NetworkManagerCpp.wifiEnabled : true
    property bool wifiConnected: NetworkManagerCpp ? NetworkManagerCpp.wifiConnected : true
    property string wifiSsid: NetworkManagerCpp ? NetworkManagerCpp.wifiSsid : "Home Network"
    property int wifiSignalStrength: NetworkManagerCpp ? NetworkManagerCpp.wifiSignalStrength : 85
    property string wifiSecurity: "WPA2"
    property string wifiIpAddress: "192.168.1.100"
    
    property bool cellularEnabled: true
    property bool cellularConnected: true
    property string cellularOperator: "Carrier"
    property string cellularTechnology: "LTE"
    property int cellularSignalStrength: 75
    property bool cellularRoaming: false
    property bool cellularDataEnabled: true
    
    property bool bluetoothEnabled: NetworkManagerCpp ? NetworkManagerCpp.bluetoothEnabled : false
    property int bluetoothConnectedDevices: 0
    
    property bool airplaneModeEnabled: NetworkManagerCpp ? NetworkManagerCpp.airplaneModeEnabled : false
    property bool vpnConnected: false
    property string vpnName: ""
    
    readonly property bool isOnline: wifiConnected || cellularConnected
    readonly property bool hasInternet: isOnline && !airplaneModeEnabled
    
    property var availableWifiNetworks: []
    property var pairedBluetoothDevices: []
    
    property bool isScanning: false
    property alias availableNetworks: networkManager.availableWifiNetworks
    
    signal networkListUpdated()
    signal connectionError(string error)
    
    function enableWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.enableWifi()
        }
    }
    
    function disableWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.disableWifi()
        }
    }
    
    function toggleWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.toggleWifi()
        }
    }
    
    function scanWifi() {
        console.log("[NetworkManager] Scanning for WiFi networks...")
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.scanWifi()
        }
    }
    
    function scanWifiNetworks() {
        scanWifi()
    }
    
    function connectToWifi(ssid, password) {
        console.log("[NetworkManager] Connecting to:", ssid)
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.connectToNetwork(ssid, password)
        }
    }
    
    function disconnectWifi() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.disconnectWifi()
        }
    }
    
    function enableCellular() {
        console.log("[NetworkManager] Enabling cellular...")
        cellularEnabled = true
    }
    
    function disableCellular() {
        console.log("[NetworkManager] Disabling cellular...")
        cellularEnabled = false
        cellularConnected = false
    }
    
    function enableBluetooth() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.enableBluetooth()
        }
    }
    
    function disableBluetooth() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.disableBluetooth()
        }
    }
    
    function toggleBluetooth() {
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.toggleBluetooth()
        }
    }
    
    function setAirplaneMode(enabled) {
        console.log("[NetworkManager] Airplane mode:", enabled)
        if (typeof NetworkManagerCpp !== 'undefined') {
            NetworkManagerCpp.setAirplaneMode(enabled)
        }
    }
    
    function enableCellularData() {
        console.log("[NetworkManager] Enabling cellular data...")
        cellularDataEnabled = true
    }
    
    function disableCellularData() {
        console.log("[NetworkManager] Disabling cellular data...")
        cellularDataEnabled = false
    }
    
    Component.onCompleted: {
        console.log("[NetworkManager] Initialized (proxying to C++ backend)")
        if (typeof NetworkManagerCpp !== 'undefined') {
            console.log("[NetworkManager] C++ backend available")
        } else {
            console.log("[NetworkManager] C++ backend not available, using mock data")
        }
    }
}

