pragma Singleton
import QtQuick

QtObject {
    id: networkManager
    
    property bool wifiEnabled: true
    property bool wifiConnected: true
    property string wifiSsid: "Home Network"
    property int wifiSignalStrength: 85
    property string wifiSecurity: "WPA2"
    property string wifiIpAddress: "192.168.1.100"
    
    property bool cellularEnabled: true
    property bool cellularConnected: true
    property string cellularOperator: "Carrier"
    property string cellularTechnology: "LTE"
    property int cellularSignalStrength: 75
    property bool cellularRoaming: false
    property bool cellularDataEnabled: true
    
    property bool bluetoothEnabled: false
    property int bluetoothConnectedDevices: 0
    
    property bool airplaneModeEnabled: false
    property bool vpnConnected: false
    property string vpnName: ""
    
    readonly property bool isOnline: wifiConnected || cellularConnected
    readonly property bool hasInternet: isOnline && !airplaneModeEnabled
    
    property var availableWifiNetworks: []
    property var pairedBluetoothDevices: []
    
    property bool isScanning: false
    property alias availableNetworks: networkManager.availableWifiNetworks
    
    property Timer scanCompleteTimer: Timer {
        interval: 2000
        onTriggered: {
            networkManager.isScanning = false
        }
    }
    
    signal networkListUpdated()
    signal connectionError(string error)
    
    function enableWifi() {
        console.log("[NetworkManager] Enabling WiFi...")
        wifiEnabled = true
        _platformEnableWifi(true)
        scanWifiNetworks()
    }
    
    function disableWifi() {
        console.log("[NetworkManager] Disabling WiFi...")
        wifiEnabled = false
        wifiConnected = false
        _platformEnableWifi(false)
    }
    
    function toggleWifi() {
        if (wifiEnabled) {
            disableWifi()
        } else {
            enableWifi()
        }
    }
    
    function scanWifi() {
        console.log("[NetworkManager] Scanning for WiFi networks...")
        isScanning = true
        _platformScanWifi()
        if (scanCompleteTimer) {
            scanCompleteTimer.start()
        }
    }
    
    function scanWifiNetworks() {
        scanWifi()
    }
    
    function connectToWifi(ssid, password) {
        console.log("[NetworkManager] Connecting to:", ssid)
        _platformConnectWifi(ssid, password)
    }
    
    function disconnectWifi() {
        console.log("[NetworkManager] Disconnecting WiFi...")
        wifiConnected = false
        wifiSsid = ""
        _platformDisconnectWifi()
    }
    
    function enableCellular() {
        console.log("[NetworkManager] Enabling cellular...")
        cellularEnabled = true
        _platformEnableCellular(true)
    }
    
    function disableCellular() {
        console.log("[NetworkManager] Disabling cellular...")
        cellularEnabled = false
        cellularConnected = false
        _platformEnableCellular(false)
    }
    
    function enableBluetooth() {
        console.log("[NetworkManager] Enabling Bluetooth...")
        bluetoothEnabled = true
        _platformEnableBluetooth(true)
    }
    
    function disableBluetooth() {
        console.log("[NetworkManager] Disabling Bluetooth...")
        bluetoothEnabled = false
        bluetoothConnectedDevices = 0
        _platformEnableBluetooth(false)
    }
    
    function toggleBluetooth() {
        if (bluetoothEnabled) {
            disableBluetooth()
        } else {
            enableBluetooth()
        }
    }
    
    function setAirplaneMode(enabled) {
        console.log("[NetworkManager] Airplane mode:", enabled)
        airplaneModeEnabled = enabled
        
        if (enabled) {
            disableWifi()
            disableCellular()
            disableBluetooth()
        }
        
        _platformSetAirplaneMode(enabled)
    }
    
    function enableCellularData() {
        console.log("[NetworkManager] Enabling cellular data...")
        cellularDataEnabled = true
        _platformEnableCellularData(true)
    }
    
    function disableCellularData() {
        console.log("[NetworkManager] Disabling cellular data...")
        cellularDataEnabled = false
        _platformEnableCellularData(false)
    }
    
    function _platformEnableWifi(enabled) {
        if (Platform.hasNetworkManager) {
            console.log("[NetworkManager] D-Bus call to NetworkManager: SetWifiEnabled")
        } else if (Platform.isMacOS) {
            console.log("[NetworkManager] macOS networksetup -setairportpower")
        }
    }
    
    function _platformScanWifi() {
        if (Platform.hasNetworkManager) {
            console.log("[NetworkManager] D-Bus call to NetworkManager: RequestScan")
        } else if (Platform.isMacOS) {
            console.log("[NetworkManager] macOS airport -s")
        } else {
            availableWifiNetworks = [
                {ssid: "Home Network", strength: 85, security: "WPA2"},
                {ssid: "Office WiFi", strength: 70, security: "WPA2"},
                {ssid: "Guest Network", strength: 50, security: "Open"}
            ]
            networkListUpdated()
        }
    }
    
    function _platformConnectWifi(ssid, password) {
        if (Platform.hasNetworkManager) {
            console.log("[NetworkManager] D-Bus call to NetworkManager: AddAndActivateConnection")
        } else if (Platform.isMacOS) {
            console.log("[NetworkManager] macOS networksetup -setairportnetwork")
        } else {
            wifiConnected = true
            wifiSsid = ssid
            wifiConnectionChanged(true, ssid)
        }
    }
    
    function _platformDisconnectWifi() {
        if (Platform.hasNetworkManager) {
            console.log("[NetworkManager] D-Bus call to NetworkManager: DeactivateConnection")
        } else if (Platform.isMacOS) {
            console.log("[NetworkManager] macOS networksetup -removepreferredwirelessnetwork")
        }
    }
    
    function _platformEnableCellular(enabled) {
        if (Platform.hasModemManager) {
            console.log("[NetworkManager] D-Bus call to ModemManager:", enabled)
        }
    }
    
    function _platformEnableBluetooth(enabled) {
        if (Platform.isLinux) {
            console.log("[NetworkManager] D-Bus call to BlueZ:", enabled)
        } else if (Platform.isMacOS) {
            console.log("[NetworkManager] macOS blueutil --power", enabled)
        }
    }
    
    function _platformSetAirplaneMode(enabled) {
        if (Platform.hasNetworkManager) {
            console.log("[NetworkManager] Setting airplane mode via rfkill")
        }
    }
    
    function _platformEnableCellularData(enabled) {
        if (Platform.hasModemManager) {
            console.log("[NetworkManager] D-Bus call to ModemManager: SetDataEnabled")
        }
    }
    
    property Timer signalMonitor: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (wifiConnected && wifiSignalStrength > 0) {
                wifiSignalStrength = Math.max(20, Math.min(100, wifiSignalStrength + Math.random() * 10 - 5))
            }
            if (cellularConnected && cellularSignalStrength > 0) {
                cellularSignalStrength = Math.max(20, Math.min(100, cellularSignalStrength + Math.random() * 10 - 5))
            }
        }
    }
    
    Component.onCompleted: {
        console.log("[NetworkManager] Initialized")
        console.log("[NetworkManager] NetworkManager available:", Platform.hasNetworkManager)
        console.log("[NetworkManager] ModemManager available:", Platform.hasModemManager)
        scanWifiNetworks()
    }
}

