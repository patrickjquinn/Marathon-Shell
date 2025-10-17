pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: wakeManager
    
    property bool systemAwake: true
    property bool screenOn: true
    property string wakeReason: ""  // alarm, notification, call, user, system
    property int wakeLockCount: 0
    
    property var scheduledWakes: []  // Array of {time: Date, reason: string, id: string}
    property var activeWakeLocks: []  // Array of {id: string, reason: string, timestamp: number}
    
    signal systemWaking(string reason)
    signal systemSleeping()
    signal wakeLockAcquired(string lockId, string reason)
    signal wakeLockReleased(string lockId)
    
    // Wake states
    readonly property bool canSleep: wakeLockCount === 0 && !hasActiveCalls && !hasActiveAlarm
    property bool hasActiveCalls: false
    property bool hasActiveAlarm: false
    
    // Sleep/wake functions
    function wake(reason) {
        Logger.info("WakeManager", "Waking system: " + reason)
        
        wakeReason = reason
        systemAwake = true
        
        // Turn on screen
        if (!screenOn) {
            DisplayManager.turnScreenOn()
            screenOn = true
        }
        
        // Unlock session if needed
        if (SessionStore.isLocked && (reason === "call" || reason === "alarm")) {
            // Show over lockscreen for calls and alarms
            Logger.info("WakeManager", "Showing " + reason + " over lockscreen")
        }
        
        // Platform-specific wake (cancel any pending suspend)
        _platformWake()
        
        systemWaking(reason)
        
        // Auto-acquire temporary wake lock
        var lockId = acquireWakeLock(reason, 30000)  // 30 second default
        return lockId
    }
    
    function sleep() {
        if (!canSleep) {
            Logger.warn("WakeManager", "Cannot sleep - wake locks active: " + wakeLockCount)
            return false
        }
        
        Logger.info("WakeManager", "Putting system to sleep")
        
        systemAwake = false
        systemSleeping()
        
        // Turn off screen first
        DisplayManager.turnScreenOff()
        screenOn = false
        
        // Platform-specific suspend to RAM (S3)
        _platformSuspend()
        
        return true
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
        Logger.info("WakeManager", "Scheduled wake in " + Math.round(msUntil / 1000 / 60) + " minutes for: " + reason)
        
        // Platform-specific RTC alarm
        _platformScheduleWake(wakeTime, reason)
        
        return wakeId
    }
    
    function cancelScheduledWake(wakeId) {
        for (var i = 0; i < scheduledWakes.length; i++) {
            if (scheduledWakes[i].id === wakeId) {
                scheduledWakes.splice(i, 1)
                scheduledWakesChanged()
                Logger.info("WakeManager", "Cancelled scheduled wake: " + wakeId)
                
                // Re-calculate next wake
                _updateNextWake()
                return true
            }
        }
        return false
    }
    
    // Wake locks (prevent sleep)
    function acquireWakeLock(reason, timeoutMs) {
        var lockId = Qt.md5(Date.now() + reason + Math.random())
        var lock = {
            id: lockId,
            reason: reason,
            timestamp: Date.now(),
            timeout: timeoutMs || 0
        }
        
        activeWakeLocks.push(lock)
        activeWakeLocksChanged()
        wakeLockCount++
        
        Logger.info("WakeManager", "Wake lock acquired: " + lockId + " (" + reason + ") - Total: " + wakeLockCount)
        wakeLockAcquired(lockId, reason)
        
        // Auto-release after timeout
        if (timeoutMs > 0) {
            Qt.callLater(function() {
                var timer = Qt.createQmlObject(
                    'import QtQuick 2.15; Timer {interval: ' + timeoutMs + '; repeat: false; running: true}',
                    wakeManager, "wakeLockTimer"
                )
                timer.triggered.connect(function() {
                    releaseWakeLock(lockId)
                    timer.destroy()
                })
            })
        }
        
        return lockId
    }
    
    function releaseWakeLock(lockId) {
        for (var i = 0; i < activeWakeLocks.length; i++) {
            if (activeWakeLocks[i].id === lockId) {
                var lock = activeWakeLocks[i]
                activeWakeLocks.splice(i, 1)
                activeWakeLocksChanged()
                wakeLockCount--
                
                Logger.info("WakeManager", "Wake lock released: " + lockId + " (" + lock.reason + ") - Total: " + wakeLockCount)
                wakeLockReleased(lockId)
                
                // Check if we can sleep now
                if (canSleep && !systemAwake) {
                    Logger.info("WakeManager", "All wake locks released, system can sleep")
                }
                
                return true
            }
        }
        return false
    }
    
    function releaseAllWakeLocks(reason) {
        var released = 0
        for (var i = activeWakeLocks.length - 1; i >= 0; i--) {
            if (!reason || activeWakeLocks[i].reason === reason) {
                releaseWakeLock(activeWakeLocks[i].id)
                released++
            }
        }
        Logger.info("WakeManager", "Released " + released + " wake locks" + (reason ? " for reason: " + reason : ""))
    }
    
    // Platform integration
    function _platformWake() {
        if (Platform.isLinux) {
            Logger.debug("WakeManager", "Linux: Inhibiting systemd sleep")
            // systemd-inhibit --what=sleep --who=marathon --why="Active wake lock"
            // OR: DBus call to org.freedesktop.login1.Manager.Inhibit
        }
    }
    
    function _platformSuspend() {
        if (Platform.isLinux && Platform.hasSystemdLogind) {
            Logger.info("WakeManager", "Linux: Suspending via systemd-logind")
            // systemctl suspend
            // OR: DBus call to org.freedesktop.login1.Manager.Suspend
            
            if (typeof PowerManagerCpp !== 'undefined') {
                PowerManagerCpp.suspend()
            }
        } else if (Platform.isMacOS) {
            Logger.info("WakeManager", "macOS: pmset sleepnow")
        }
    }
    
    function _platformScheduleWake(wakeTime, reason) {
        if (Platform.isLinux) {
            Logger.info("WakeManager", "Linux: Setting RTC wake alarm")
            // echo 0 > /sys/class/rtc/rtc0/wakealarm  # Clear existing
            // echo {epoch_time} > /sys/class/rtc/rtc0/wakealarm  # Set new
            //
            // OR: systemd timer with WakeSystem=true
            //
            // We need C++ helper for sysfs access
            var epochTime = Math.floor(wakeTime.getTime() / 1000)
            
            if (typeof WakeManagerCpp !== 'undefined') {
                WakeManagerCpp.setRtcWake(epochTime)
            } else {
                Logger.warn("WakeManager", "WakeManagerCpp not available - wake scheduling unavailable")
            }
        }
    }
    
    function _updateNextWake() {
        if (scheduledWakes.length === 0) {
            Logger.info("WakeManager", "No scheduled wakes")
            return
        }
        
        // Find nearest wake
        var now = new Date()
        var nearest = null
        var nearestTime = null
        
        for (var i = 0; i < scheduledWakes.length; i++) {
            var wake = scheduledWakes[i]
            if (wake.time > now && (!nearestTime || wake.time < nearestTime)) {
                nearest = wake
                nearestTime = wake.time
            }
        }
        
        if (nearest) {
            Logger.info("WakeManager", "Next wake: " + nearest.reason + " at " + nearestTime)
            _platformScheduleWake(nearestTime, nearest.reason)
        }
    }
    
    // Handle system resume event (from suspend)
    function _handleSystemResume() {
        Logger.info("WakeManager", "System resumed from suspend")
        
        systemAwake = true
        screenOn = true
        
        // Check why we woke up
        var now = new Date()
        for (var i = scheduledWakes.length - 1; i >= 0; i--) {
            var wake = scheduledWakes[i]
            if (wake.time <= now) {
                Logger.info("WakeManager", "Wake triggered: " + wake.reason)
                wake(wake.reason)
                
                // Remove this wake
                scheduledWakes.splice(i, 1)
                scheduledWakesChanged()
            }
        }
        
        // Update next wake
        _updateNextWake()
    }
    
    // Monitor for incoming events that should wake the system
    Connections {
        target: typeof NotificationService !== 'undefined' ? NotificationService : null
        
        function onNotificationReceived(notification) {
            if (!systemAwake && notification.priority === "high") {
                wake("notification")
            }
        }
    }
    
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
    
    // Handle call states (when TelephonyManager exists)
    Connections {
        target: typeof TelephonyManager !== 'undefined' ? TelephonyManager : null
        
        function onIncomingCall(callId, number) {
            hasActiveCalls = true
            wake("call")
        }
        
        function onCallEnded(callId) {
            hasActiveCalls = false
        }
    }
    
    Component.onCompleted: {
        Logger.info("WakeManager", "Initialized")
        Logger.info("WakeManager", "Platform sleep support: " + (Platform.hasSystemdLogind ? "systemd-logind" : "unavailable"))
        
        // Initial state
        systemAwake = true
        screenOn = DisplayManager.screenOn
    }
}

