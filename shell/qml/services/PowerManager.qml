pragma Singleton
import QtQuick

QtObject {
    id: powerManager
    
    property int batteryLevel: 75
    property bool isCharging: false
    property bool isPowerSaveMode: false
    property string powerState: "normal"
    property int estimatedBatteryTime: -1
    property string batteryHealth: "good"
    property real batteryVoltage: 0.0
    property real batteryTemperature: 0.0
    
    readonly property bool isCritical: batteryLevel <= 5
    readonly property bool isLow: batteryLevel <= 20
    readonly property bool isFull: batteryLevel >= 95 && isCharging
    
    property bool canSuspend: true
    property bool canHibernate: true
    property bool canHybridSleep: Platform.isLinux
    property bool canShutdown: true
    property bool canRestart: true
    
    signal criticalBattery()
    
    function suspend() {
        console.log("[PowerManager] Suspending system...")
        ServiceBus.systemSuspending()
        _platformSuspend()
    }
    
    function hibernate() {
        console.log("[PowerManager] Hibernating system...")
        _platformHibernate()
    }
    
    function shutdown() {
        console.log("[PowerManager] Shutting down...")
        ServiceBus.systemShuttingDown()
        _platformShutdown()
    }
    
    function restart() {
        console.log("[PowerManager] Restarting...")
        _platformRestart()
    }
    
    function setPowerSaveMode(enabled) {
        console.log("[PowerManager] Power save mode:", enabled)
        isPowerSaveMode = enabled
        powerSaveModeChanged(enabled)
        _platformSetPowerSaveMode(enabled)
    }
    
    function refreshBatteryInfo() {
        _platformRefreshBattery()
    }
    
    function _platformSuspend() {
        if (Platform.hasSystemdLogind) {
            _dbusCallSystemd("Suspend", [true])
        } else if (Platform.isMacOS) {
            _macOSSuspend()
        }
    }
    
    function _platformHibernate() {
        if (Platform.hasSystemdLogind) {
            _dbusCallSystemd("Hibernate", [true])
        }
    }
    
    function _platformShutdown() {
        if (Platform.hasSystemdLogind) {
            _dbusCallSystemd("PowerOff", [true])
        } else if (Platform.isMacOS) {
            _macOSShutdown()
        }
    }
    
    function _platformRestart() {
        if (Platform.hasSystemdLogind) {
            _dbusCallSystemd("Reboot", [true])
        } else if (Platform.isMacOS) {
            _macOSRestart()
        }
    }
    
    function _platformSetPowerSaveMode(enabled) {
        if (Platform.hasUPower) {
            console.log("[PowerManager] UPower power save mode:", enabled)
        } else if (Platform.isMacOS) {
            console.log("[PowerManager] macOS low power mode:", enabled)
        }
    }
    
    function _platformRefreshBattery() {
        if (Platform.hasUPower) {
            console.log("[PowerManager] Querying UPower for battery info...")
        } else if (Platform.isMacOS) {
            _macOSRefreshBattery()
        } else {
            _simulateBatteryUpdate()
        }
    }
    
    function _dbusCallSystemd(method, args) {
        console.log("[PowerManager] D-Bus call to systemd-logind:", method)
    }
    
    function _macOSSuspend() {
        console.log("[PowerManager] macOS suspend via pmset sleepnow")
    }
    
    function _macOSShutdown() {
        console.log("[PowerManager] macOS shutdown via osascript")
    }
    
    function _macOSRestart() {
        console.log("[PowerManager] macOS restart via osascript")
    }
    
    function _macOSRefreshBattery() {
        console.log("[PowerManager] macOS battery info via pmset -g batt")
    }
    
    function _simulateBatteryUpdate() {
        batteryLevel = Math.max(0, Math.min(100, batteryLevel + (isCharging ? 1 : -1)))
        
        if (batteryLevel <= 5 && !isCharging) {
            criticalBattery()
        }
    }
    
    property Timer batterySimulator: Timer {
        interval: 60000
        running: !Platform.hasUPower && !Platform.isMacOS
        repeat: true
        onTriggered: _simulateBatteryUpdate()
    }
    
    property Timer batteryPoller: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: refreshBatteryInfo()
    }
    
    Component.onCompleted: {
        console.log("[PowerManager] Initialized")
        console.log("[PowerManager] UPower available:", Platform.hasUPower)
        console.log("[PowerManager] systemd-logind available:", Platform.hasSystemdLogind)
        refreshBatteryInfo()
    }
}

