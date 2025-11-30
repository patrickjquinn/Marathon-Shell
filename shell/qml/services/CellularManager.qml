pragma Singleton
import QtQuick
import MarathonOS.Shell

Item {
    id: cellularManager

    // Modem state
    property bool modemAvailable: false
    property bool modemEnabled: true
    property string modemState: "registered" // registered, searching, denied, unknown
    property int modemSignalStrength: 0  // 0-100

    // Network registration
    property bool registered: false
    property string operatorName: ""
    property string operatorMcc: ""  // Mobile Country Code
    property string operatorMnc: ""  // Mobile Network Code
    property string networkType: "LTE"  // GSM, EDGE, 3G, HSPA, LTE, 5G
    property bool roaming: false

    // Data connection
    property bool dataEnabled: true
    property bool dataConnected: false
    property string accessPointName: ""
    property string ipAddress: ""

    // SIM state
    property bool simPresent: false
    property string simOperator: ""
    property string phoneNumber: ""
    property string imei: ""
    property string iccid: ""

    // Data usage
    property real dataUsageMB: 0.0
    property real dataLimitMB: 0.0
    property bool dataLimitEnabled: false

    signal networkRegistered(string operator)
    signal networkLost
    signal dataConnectionChanged(bool connected)
    signal signalStrengthChanged(int strength)
    signal roamingStatusChanged(bool roaming)

    // Modem control
    function enableModem() {
        Logger.info("CellularManager", "Enabling modem");
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.enable();
        }
        modemEnabled = true;
    }

    function disableModem() {
        Logger.info("CellularManager", "Disabling modem");
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.disable();
        }
        modemEnabled = false;
        registered = false;
        dataConnected = false;
    }

    function toggleModem() {
        if (modemEnabled) {
            disableModem();
        } else {
            enableModem();
        }
    }

    // Data control
    function enableData() {
        Logger.info("CellularManager", "Enabling mobile data");
        dataEnabled = true;
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.enableData();
        }
    }

    function disableData() {
        Logger.info("CellularManager", "Disabling mobile data");
        dataEnabled = false;
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.disableData();
        }
    }

    function toggleData() {
        if (dataEnabled) {
            disableData();
        } else {
            enableData();
        }
    }

    // Network selection
    function scanNetworks() {
        Logger.info("CellularManager", "Scanning for networks");
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.scanNetworks();
        }
    }

    function selectNetwork(operatorId) {
        Logger.info("CellularManager", "Selecting network: " + operatorId);
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.selectNetwork(operatorId);
        }
    }

    function setAutoNetwork() {
        Logger.info("CellularManager", "Setting automatic network selection");
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.setAutoNetworkSelection();
        }
    }

    // APN configuration
    function setApn(name, username, password) {
        Logger.info("CellularManager", "Setting APN: " + name);
        accessPointName = name;
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.setApn(name, username, password);
        }
    }

    // Data usage
    function resetDataUsage() {
        Logger.info("CellularManager", "Resetting data usage counter");
        dataUsageMB = 0.0;
        if (typeof ModemManagerCpp !== 'undefined') {
            ModemManagerCpp.resetDataUsage();
        }
    }

    function setDataLimit(limitMB) {
        Logger.info("CellularManager", "Setting data limit: " + limitMB + " MB");
        dataLimitMB = limitMB;
        dataLimitEnabled = limitMB > 0;
    }

    // Platform integration (Linux ModemManager via DBus)
    function _initializeModemManager() {
        if (Platform.isLinux) {
            Logger.info("CellularManager", "Initializing ModemManager via DBus");
            // ModemManager DBus service: org.freedesktop.ModemManager1
            // Path: /org/freedesktop/ModemManager1
            _pollModemState();
        } else {
            Logger.warn("CellularManager", "Cellular not supported on this platform");
        }
    }

    function _pollModemState() {
        // In production, this would listen to DBus signals
        // For now, we'll use a timer to check state
        if (typeof ModemManagerCpp !== 'undefined') {
            modemAvailable = ModemManagerCpp.modemAvailable;
            modemSignalStrength = ModemManagerCpp.signalStrength;
            registered = ModemManagerCpp.registered;
            operatorName = ModemManagerCpp.operatorName;
            networkType = ModemManagerCpp.networkType;
            roaming = ModemManagerCpp.roaming;
            simPresent = ModemManagerCpp.simPresent;
        }
    }

    Component.onCompleted: {
        Logger.info("CellularManager", "Initialized");
        _initializeModemManager();

        // Poll modem state every 10 seconds
        stateTimer.start();
    }

    property var stateTimer: Timer {
        id: stateTimer
        interval: 10000
        repeat: true
        running: false
        onTriggered: _pollModemState()
    }
}
