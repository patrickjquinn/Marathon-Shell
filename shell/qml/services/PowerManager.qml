pragma Singleton
import MarathonOS.Shell
import QtQuick

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
    // ============================================================================
    // Wakelock Management (merged from WakeManager)
    // ============================================================================
    // ============================================================================
    // Wakelock Functions
    // ============================================================================
    // ============================================================================
    // RTC Alarm Functions
    // ============================================================================
    // ============================================================================
    // C++ Signal Connections
    // ============================================================================
    // ============================================================================
    // Integration with other services
    // ============================================================================
    //*
    //     * @brief Whether device is currently charging
    //     * @type {bool}
    //     * @readonly
    //*
    //     * @brief Whether device is currently charging
    //     * @type {bool}
    //     * @readonly

    id: powerManager

    /**
     * @brief Current battery level (0-100)
     * @type {int}
     * @readonly
     */
    property int batteryLevel: PowerManagerService ? PowerManagerService.batteryLevel : 75
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
    property real batteryVoltage: 0
    property real batteryTemperature: 0
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
    property bool systemAwake: !systemSuspended
    property bool screenOn: true
    property string wakeReason: ""
    // Wakelock + sleep policy moved to C++ (PowerPolicyControllerCpp)
    readonly property int wakeLockCount: (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp) ? PowerPolicyControllerCpp.wakeLockCount : 0
    property bool hasActiveCalls: (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp) ? PowerPolicyControllerCpp.hasActiveCalls : false
    property bool hasActiveAlarm: (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp) ? PowerPolicyControllerCpp.hasActiveAlarm : false
    readonly property bool canSleep: (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp) ? PowerPolicyControllerCpp.canSleep : (wakeLockCount === 0 && !hasActiveCalls && !hasActiveAlarm)
    readonly property bool systemSuspended: PowerManagerService ? PowerManagerService.systemSuspended : false
    readonly property bool wakelockSupported: PowerManagerService ? PowerManagerService.wakelockSupported : false
    readonly property bool rtcAlarmSupported: PowerManagerService ? PowerManagerService.rtcAlarmSupported : false

    signal systemWaking(string reason)
    signal systemSleeping
    signal wakeLockAcquired(string lockId, string reason)
    signal wakeLockReleased(string lockId)
    /**
     * @brief Emitted when battery reaches critical level (5%)
     */
    signal criticalBattery

    /**
     * @brief Suspends the system to RAM (sleep mode)
     *
     * System state is preserved in memory. Quick resume but uses some power.
     * Requires canSuspend to be true.
     */
    function suspend() {
        console.log("[PowerManager] Suspending system...");
        if (typeof PowerManagerService !== 'undefined')
            PowerManagerService.suspend();
    }

    /**
     * @brief Hibernates the system to disk
     *
     * System state is saved to disk and powered off. Slower resume but no power usage.
     * Requires canHibernate to be true.
     */
    function hibernate() {
        console.log("[PowerManager] Hibernating system...");
        if (typeof PowerManagerService !== 'undefined')
            PowerManagerService.hibernate();
    }

    /**
     * @brief Shuts down the system completely
     *
     * Powers off the device. Requires canShutdown to be true.
     */
    function shutdown() {
        console.log("[PowerManager] Shutting down...");
        if (typeof PowerManagerService !== 'undefined')
            PowerManagerService.shutdown();
    }

    /**
     * @brief Restarts the system
     *
     * Reboots the device. Requires canRestart to be true.
     */
    function restart() {
        console.log("[PowerManager] Restarting...");
        if (typeof PowerManagerService !== 'undefined')
            PowerManagerService.restart();
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
        console.log("[PowerManager] Power save mode:", enabled);
        if (typeof PowerManagerService !== 'undefined')
            PowerManagerService.setPowerSaveMode(enabled);
    }

    function togglePowerSaveMode() {
        setPowerSaveMode(!isPowerSaveMode);
    }

    function refreshBatteryInfo() {
        if (typeof PowerManagerService !== 'undefined')
            PowerManagerService.refreshBatteryInfo();
    }

    function acquireWakelock(name) {
        if (typeof PowerManagerService !== 'undefined')
            return PowerManagerService.acquireWakelock(name);

        return false;
    }

    function releaseWakelock(name) {
        if (typeof PowerManagerService !== 'undefined')
            return PowerManagerService.releaseWakelock(name);

        return false;
    }

    function hasWakelock(name) {
        if (typeof PowerManagerService !== 'undefined')
            return PowerManagerService.hasWakelock(name);

        return false;
    }

    function wake(reason) {
        Logger.info("PowerManager", "Waking system: " + reason);
        wakeReason = reason;
        systemAwake = true;
        systemWaking(reason);
        if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp)
            return PowerPolicyControllerCpp.wake(reason);

        // Fallback: acquire temporary wakelock
        return acquireWakelock(reason);
    }

    function sleep() {
        if (!canSleep) {
            Logger.warn("PowerManager", "Cannot sleep - wake locks active: " + wakeLockCount);
            return false;
        }
        Logger.info("PowerManager", "Putting system to sleep");
        systemAwake = false;
        systemSleeping();
        if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp)
            return PowerPolicyControllerCpp.sleep();

        suspend();
        return true;
    }

    function setRtcAlarm(epochTime) {
        if (typeof PowerManagerService !== 'undefined')
            return PowerManagerService.setRtcAlarm(epochTime);

        return false;
    }

    function clearRtcAlarm() {
        if (typeof PowerManagerService !== 'undefined')
            return PowerManagerService.clearRtcAlarm();

        return false;
    }

    function scheduleWake(wakeTime, reason) {
        var epochTime = Math.floor(wakeTime.getTime() / 1000);
        Logger.info("PowerManager", "Scheduled wake (epoch=" + epochTime + ") for: " + reason);
        if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp)
            return PowerPolicyControllerCpp.scheduleWakeEpoch(epochTime, reason);

        // Fallback: directly set RTC alarm
        setRtcAlarm(epochTime);
        return Qt.md5(Date.now() + reason);
    }

    function cancelScheduledWake(wakeId) {
        if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp)
            return PowerPolicyControllerCpp.cancelScheduledWake(wakeId);

        return false;
    }

    Component.onCompleted: {
        console.log("[PowerManager] Initialized (merged with WakeManager)");
        if (typeof PowerManagerService !== 'undefined') {
            console.log("[PowerManager] C++ backend available");
            console.log("[PowerManager] Wakelock support:", wakelockSupported);
            console.log("[PowerManager] RTC alarm support:", rtcAlarmSupported);
        } else {
            console.log("[PowerManager] C++ backend not available, using mock data");
        }
        // Initial state
        systemAwake = true;
        screenOn = DisplayManager ? DisplayManager.screenOn : true;
    }

    Connections {
        function onPrepareForSuspend() {
            Logger.info("PowerManager", "System preparing to suspend");
            systemSleeping();
        }

        function onResumedFromSuspend() {
            Logger.info("PowerManager", "System resumed from suspend");
            systemAwake = true;
            systemWaking("resume");
        }

        target: typeof PowerManagerService !== 'undefined' ? PowerManagerService : null
    }

    Connections {
        function onAlarmTriggered(alarm) {
            hasActiveAlarm = true;
            wake("alarm");
        }

        function onAlarmDismissed(alarmId) {
            hasActiveAlarm = false;
        }

        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null
    }
}
