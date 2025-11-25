pragma Singleton
import QtQuick
import MarathonOS.Shell

/**
 * @singleton
 * @brief Manages device power state and battery monitoring
 * 
 * PowerManager provides access to battery status, power state, and system
 * power actions (suspend, hibernate, shutdown, restart). Integrates with
 * C++ backend (PowerManagerService) for actual hardware control.
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
Item {
    id: powerManager
    
    /**
     * @brief Current battery level (0-100)
     * @type {int}
     * @readonly
     */
    property int batteryLevel: PowerManagerService ? PowerManagerService.batteryLevel : 75
    
    /**
     * @brief Whether device is currently charging
     * @type {bool}
     * @readonly
     */
    /**
     * @brief Whether device is currently charging
     * @type {bool}
     * @readonly
     */
    property bool isCharging: PowerManagerService ? PowerManagerService.isCharging : false
    
    /**
     * @brief Whether device is plugged into power source (charging or fully charged)
     * @type {bool}
     * @readonly
     */
    property bool isPluggedIn: PowerManagerService ? PowerManagerService.isPluggedIn : false
    
    
    /**
     * @brief Whether power saving mode is active
     * @type {bool}
     */
    property bool isPowerSaveMode: PowerManagerService ? PowerManagerService.isPowerSaveMode : false
    
    property string powerState: "normal"
    
    /**
     * @brief Estimated minutes until battery depleted (-1 if charging or unknown)
     * @type {int}
     * @readonly
     */
    property int estimatedBatteryTime: PowerManagerService ? PowerManagerService.estimatedBatteryTime : -1
    
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
    
    // ============================================================================
    // Wakelock Management (merged from WakeManager)
    // ============================================================================
    
    property var activeWakelocks: []
    property var scheduledWakes: []
    property bool systemAwake: !systemSuspended
    property bool screenOn: true
    property string wakeReason: ""
    property int wakeLockCount: activeWakelocks.length
    property bool hasActiveCalls: false
    property bool hasActiveAlarm: false
    
    readonly property bool canSleep: wakeLockCount === 0 && !hasActiveCalls && !hasActiveAlarm
    readonly property bool systemSuspended: PowerManagerService ? PowerManagerService.systemSuspended : false
    readonly property bool wakelockSupported: PowerManagerService ? PowerManagerService.wakelockSupported : false
    readonly property bool rtcAlarmSupported: PowerManagerService ? PowerManagerService.rtcAlarmSupported : false
    
    signal systemWaking(string reason)
    signal systemSleeping()
    signal wakeLockAcquired(string lockId, string reason)
    signal wakeLockReleased(string lockId)
    
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
        if (typeof PowerManagerService !== 'undefined') {
            PowerManagerService.suspend()
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
        if (typeof PowerManagerService !== 'undefined') {
            PowerManagerService.hibernate()
        }
    }
    
    /**
     * @brief Shuts down the system completely
     * 
     * Powers off the device. Requires canShutdown to be true.
     */
    function shutdown() {
        console.log("[PowerManager] Shutting down...")
        if (typeof PowerManagerService !== 'undefined') {
            PowerManagerService.shutdown()
        }
    }
    
    /**
     * @brief Restarts the system
     * 
     * Reboots the device. Requires canRestart to be true.
     */
    function restart() {
        console.log("[PowerManager] Restarting...")
        if (typeof PowerManagerService !== 'undefined') {
            PowerManagerService.restart()
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
        if (typeof PowerManagerService !== 'undefined') {
            PowerManagerService.setPowerSaveMode(enabled)
        }
    }
    
    function togglePowerSaveMode() {
        setPowerSaveMode(!isPowerSaveMode)
    }
    
    function refreshBatteryInfo() {
        if (typeof PowerManagerService !== 'undefined') {
            PowerManagerService.refreshBatteryInfo()
        }
    }
    
    // ============================================================================
    // Wakelock Functions
    // ============================================================================
    
    function acquireWakelock(name) {
        if (typeof PowerManagerService !== 'undefined') {
            var success = PowerManagerService.acquireWakelock(name)
            if (success) {
                var lock = {
                    id: name,
                    reason: name,
                    timestamp: Date.now()
                }
                activeWakelocks.push(lock)
                activeWakelocksChanged()
                Logger.info("PowerManager", "Acquired wakelock: " + name)
                wakeLockAcquired(name, name)
            }
            return success
        }
        return false
    }
    
    function releaseWakelock(name) {
        if (typeof PowerManagerService !== 'undefined') {
            var success = PowerManagerService.releaseWakelock(name)
            if (success) {
                for (var i = 0; i < activeWakelocks.length; i++) {
                    if (activeWakelocks[i].id === name) {
                        activeWakelocks.splice(i, 1)
                        activeWakelocksChanged()
                        Logger.info("PowerManager", "Released wakelock: " + name)
                        wakeLockReleased(name)
                        break
                    }
                }
            }
            return success
        }
        return false
    }
    
    function hasWakelock(name) {
        if (typeof PowerManagerService !== 'undefined') {
            return PowerManagerService.hasWakelock(name)
        }
        return false
    }
    
    function wake(reason) {
        Logger.info("PowerManager", "Waking system: " + reason)
        wakeReason = reason
        systemAwake = true
        
        // Turn on screen if needed
        if (!screenOn && DisplayManager) {
            DisplayManager.turnScreenOn()
            screenOn = true
        }
        
        systemWaking(reason)
        
        // Auto-acquire temporary wake lock
        var lockId = acquireWakelock(reason)
        return lockId
    }
    
    function sleep() {
        if (!canSleep) {
            Logger.warn("PowerManager", "Cannot sleep - wake locks active: " + wakeLockCount)
            return false
        }
        
        Logger.info("PowerManager", "Putting system to sleep")
        systemAwake = false
        systemSleeping()
        
        // Turn off screen first
        if (DisplayManager) {
            DisplayManager.turnScreenOff()
            screenOn = false
        }
        
        // Suspend via C++ backend
        suspend()
        return true
    }
    
    // ============================================================================
    // RTC Alarm Functions
    // ============================================================================
    
    function setRtcAlarm(epochTime) {
        if (typeof PowerManagerService !== 'undefined') {
            return PowerManagerService.setRtcAlarm(epochTime)
        }
        return false
    }
    
    function clearRtcAlarm() {
        if (typeof PowerManagerService !== 'undefined') {
            return PowerManagerService.clearRtcAlarm()
        }
        return false
    }
    
    function scheduleWake(wakeTime, reason) {
        var wakeId = Qt.md5(Date.now() + reason)
        var wake = {
            id: wakeId,
            time: wakeTime,
            reason: reason,
            timestamp: Date.now()
        }
        
        scheduledWakes.push(wake)
        scheduledWakesChanged()
        
        var msUntil = wakeTime - new Date()
        Logger.info("PowerManager", "Scheduled wake in " + Math.round(msUntil / 1000 / 60) + " minutes for: " + reason)
        
        // Set RTC alarm
        var epochTime = Math.floor(wakeTime.getTime() / 1000)
        setRtcAlarm(epochTime)
        
        return wakeId
    }
    
    function cancelScheduledWake(wakeId) {
        for (var i = 0; i < scheduledWakes.length; i++) {
            if (scheduledWakes[i].id === wakeId) {
                scheduledWakes.splice(i, 1)
                scheduledWakesChanged()
                Logger.info("PowerManager", "Cancelled scheduled wake: " + wakeId)
                return true
            }
        }
        return false
    }
    
    // ============================================================================
    // C++ Signal Connections
    // ============================================================================
    
    Connections {
        target: typeof PowerManagerService !== 'undefined' ? PowerManagerService : null
        
        function onPrepareForSuspend() {
            Logger.info("PowerManager", "System preparing to suspend")
            systemSleeping()
        }
        
        function onResumedFromSuspend() {
            Logger.info("PowerManager", "System resumed from suspend")
            systemAwake = true
            systemWaking("resume")
        }
    }
    
    // ============================================================================
    // Integration with other services
    // ============================================================================
    
    Connections {
        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null
        
        function onAlarmTriggered(alarm) {
            hasActiveAlarm = true
            wake("alarm")
        }
        
        function onAlarmDismissed(alarmId) {
            hasActiveAlarm = false
        }
    }
    
    Component.onCompleted: {
        console.log("[PowerManager] Initialized (merged with WakeManager)")
        if (typeof PowerManagerService !== 'undefined') {
            console.log("[PowerManager] C++ backend available")
            console.log("[PowerManager] Wakelock support:", wakelockSupported)
            console.log("[PowerManager] RTC alarm support:", rtcAlarmSupported)
        } else {
            console.log("[PowerManager] C++ backend not available, using mock data")
        }
        
        // Initial state
        systemAwake = true
        screenOn = DisplayManager ? DisplayManager.screenOn : true
    }
}

