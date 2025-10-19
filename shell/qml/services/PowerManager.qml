pragma Singleton
import QtQuick

/**
 * @singleton
 * @brief Manages device power state and battery monitoring
 * 
 * PowerManager provides access to battery status, power state, and system
 * power actions (suspend, hibernate, shutdown, restart). Integrates with
 * C++ backend (PowerManagerCpp) for actual hardware control.
 * 
 * @example
 * // Monitor battery level
 * Text {
 *     text: "Battery: " + PowerManager.batteryLevel + "%"
 *     color: PowerManager.isLow ? "red" : "white"
 * }
 * 
 * @example
 * // Suspend system
 * Button {
 *     text: "Sleep"
 *     onClicked: PowerManager.suspend()
 * }
 */
QtObject {
    id: powerManager
    
    /**
     * @brief Current battery level (0-100)
     * @type {int}
     * @readonly
     */
    property int batteryLevel: PowerManagerCpp ? PowerManagerCpp.batteryLevel : 75
    
    /**
     * @brief Whether device is currently charging
     * @type {bool}
     * @readonly
     */
    property bool isCharging: PowerManagerCpp ? PowerManagerCpp.isCharging : false
    
    /**
     * @brief Whether power saving mode is active
     * @type {bool}
     */
    property bool isPowerSaveMode: PowerManagerCpp ? PowerManagerCpp.isPowerSaveMode : false
    
    property string powerState: "normal"
    
    /**
     * @brief Estimated minutes until battery depleted (-1 if charging or unknown)
     * @type {int}
     * @readonly
     */
    property int estimatedBatteryTime: PowerManagerCpp ? PowerManagerCpp.estimatedBatteryTime : -1
    
    property string batteryHealth: "good"
    property real batteryVoltage: 0.0
    property real batteryTemperature: 0.0
    
    /**
     * @brief Whether battery is critically low (<= 5%)
     * @type {bool}
     * @readonly
     */
    readonly property bool isCritical: batteryLevel <= 5
    
    /**
     * @brief Whether battery is low (<= 20%)
     * @type {bool}
     * @readonly
     */
    readonly property bool isLow: batteryLevel <= 20
    
    /**
     * @brief Whether battery is full (>= 95% and charging)
     * @type {bool}
     * @readonly
     */
    readonly property bool isFull: batteryLevel >= 95 && isCharging
    
    /**
     * @brief Whether system can suspend to RAM
     * @type {bool}
     */
    property bool canSuspend: true
    
    /**
     * @brief Whether system can hibernate to disk
     * @type {bool}
     */
    property bool canHibernate: true
    
    property bool canHybridSleep: false
    
    /**
     * @brief Whether system can shutdown
     * @type {bool}
     */
    property bool canShutdown: true
    
    /**
     * @brief Whether system can restart
     * @type {bool}
     */
    property bool canRestart: true
    
    /**
     * @brief Emitted when battery reaches critical level (5%)
     */
    signal criticalBattery()
    
    /**
     * @brief Suspends the system to RAM (sleep mode)
     * 
     * System state is preserved in memory. Quick resume but uses some power.
     * Requires canSuspend to be true.
     */
    function suspend() {
        console.log("[PowerManager] Suspending system...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.suspend()
        }
    }
    
    /**
     * @brief Hibernates the system to disk
     * 
     * System state is saved to disk and powered off. Slower resume but no power usage.
     * Requires canHibernate to be true.
     */
    function hibernate() {
        console.log("[PowerManager] Hibernating system...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.hibernate()
        }
    }
    
    /**
     * @brief Shuts down the system completely
     * 
     * Powers off the device. Requires canShutdown to be true.
     */
    function shutdown() {
        console.log("[PowerManager] Shutting down...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.shutdown()
        }
    }
    
    /**
     * @brief Restarts the system
     * 
     * Reboots the device. Requires canRestart to be true.
     */
    function restart() {
        console.log("[PowerManager] Restarting...")
        if (typeof PowerManagerCpp !== 'undefined') {
            PowerManagerCpp.restart()
        }
    }
    
    /**
     * @brief Enables or disables power saving mode
     * 
     * @param {bool} enabled - Whether to enable power save mode
     * 
     * Power save mode typically reduces CPU frequency, dims display,
     * and limits background processes to extend battery life.
     */
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

