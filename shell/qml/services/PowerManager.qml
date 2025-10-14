pragma Singleton
import QtQuick

QtObject {
    id: powerManager
    
    property int batteryLevel: PowerManagerCpp ? PowerManagerCpp.batteryLevel : 75
    property bool isCharging: PowerManagerCpp ? PowerManagerCpp.isCharging : false
    property bool isPowerSaveMode: PowerManagerCpp ? PowerManagerCpp.isPowerSaveMode : false
    property string powerState: "normal"
    property int estimatedBatteryTime: PowerManagerCpp ? PowerManagerCpp.estimatedBatteryTime : -1
    property string batteryHealth: "good"
    property real batteryVoltage: 0.0
    property real batteryTemperature: 0.0
    
    readonly property bool isCritical: batteryLevel <= 5
    readonly property bool isLow: batteryLevel <= 20
    readonly property bool isFull: batteryLevel >= 95 && isCharging
    
    property bool canSuspend: true
    property bool canHibernate: true
    property bool canHybridSleep: false
    property bool canShutdown: true
    property bool canRestart: true
    
    signal criticalBattery()
    
    function suspend() {
        console.log("[PowerManager] Suspending system...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.suspend()
        }
    }
    
    function hibernate() {
        console.log("[PowerManager] Hibernating system...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.hibernate()
        }
    }
    
    function shutdown() {
        console.log("[PowerManager] Shutting down...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.shutdown()
        }
    }
    
    function restart() {
        console.log("[PowerManager] Restarting...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.restart()
        }
    }
    
    function setPowerSaveMode(enabled) {
        console.log("[PowerManager] Power save mode:", enabled)
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.setPowerSaveMode(enabled)
        }
    }
    
    function refreshBatteryInfo() {
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.refreshBatteryInfo()
        }
    }
    
    Component.onCompleted: {
        console.log("[PowerManager] Initialized (proxying to C++ backend)")
        if (typeof PowerManagerCpp !== 'undefined') {
            console.log("[PowerManager] C++ backend available")
        } else {
            console.log("[PowerManager] C++ backend not available, using mock data")
        }
    }
}

