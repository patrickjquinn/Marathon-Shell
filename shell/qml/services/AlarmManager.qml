pragma Singleton
import QtQuick
import MarathonOS.Shell

Item {
    id: alarmManager

    property var alarms: []  // Array of alarm objects
    property var activeAlarms: []  // Currently ringing alarms
    property bool hasActiveAlarm: activeAlarms.length > 0

    signal alarmTriggered(var alarm)
    signal alarmDismissed(string alarmId)
    signal alarmSnoozed(string alarmId, int minutes)
    signal alarmCreated(var alarm)
    signal alarmUpdated(var alarm)
    signal alarmDeleted(string alarmId)

    // Alarm object structure:
    // {
    //   id: string,
    //   time: "HH:MM",
    //   enabled: bool,
    //   label: string,
    //   repeat: [0,1,2,3,4,5,6], // days of week, 0 = Sunday
    //   sound: string,
    //   vibrate: bool,
    //   snoozeEnabled: bool,
    //   snoozeDuration: int (minutes)
    // }

    function createAlarm(time, label, repeat, options) {
        var alarm = {
            id: Qt.md5(Date.now() + time + label),
            time: time,
            enabled: true,
            label: label || "Alarm",
            repeat: repeat || [],
            sound: (options && options.sound) || "default",
            vibrate: (options && options.vibrate) !== false,
            snoozeEnabled: (options && options.snoozeEnabled) !== false,
            snoozeDuration: (options && options.snoozeDuration) || 10
        };

        alarms.push(alarm);
        alarmsChanged();
        _saveAlarms();
        _scheduleNextAlarm();

        Logger.info("AlarmManager", "Alarm created: " + alarm.id + " at " + time);
        alarmCreated(alarm);

        return alarm.id;
    }

    function updateAlarm(alarmId, updates) {
        for (var i = 0; i < alarms.length; i++) {
            if (alarms[i].id === alarmId) {
                // Update properties
                for (var key in updates) {
                    alarms[i][key] = updates[key];
                }
                alarmsChanged();
                _saveAlarms();
                _scheduleNextAlarm();

                Logger.info("AlarmManager", "Alarm updated: " + alarmId);
                alarmUpdated(alarms[i]);
                return true;
            }
        }
        return false;
    }

    function deleteAlarm(alarmId) {
        for (var i = 0; i < alarms.length; i++) {
            if (alarms[i].id === alarmId) {
                alarms.splice(i, 1);
                alarmsChanged();
                _saveAlarms();
                _scheduleNextAlarm();

                Logger.info("AlarmManager", "Alarm deleted: " + alarmId);
                alarmDeleted(alarmId);
                return true;
            }
        }
        return false;
    }

    function enableAlarm(alarmId) {
        return updateAlarm(alarmId, {
            enabled: true
        });
    }

    function disableAlarm(alarmId) {
        return updateAlarm(alarmId, {
            enabled: false
        });
    }

    function toggleAlarm(alarmId) {
        for (var i = 0; i < alarms.length; i++) {
            if (alarms[i].id === alarmId) {
                return updateAlarm(alarmId, {
                    enabled: !alarms[i].enabled
                });
            }
        }
        return false;
    }

    function snoozeAlarm(alarmId) {
        for (var i = 0; i < activeAlarms.length; i++) {
            if (activeAlarms[i].id === alarmId) {
                var alarm = activeAlarms[i];
                var snoozeDuration = alarm.snoozeDuration || 10;

                // Remove from active
                activeAlarms.splice(i, 1);
                activeAlarmsChanged();

                // Schedule wake for snooze
                _scheduleSnooze(alarm, snoozeDuration);

                Logger.info("AlarmManager", "Alarm snoozed: " + alarmId + " for " + snoozeDuration + " minutes");
                alarmSnoozed(alarmId, snoozeDuration);

                return true;
            }
        }
        return false;
    }

    function dismissAlarm(alarmId) {
        for (var i = 0; i < activeAlarms.length; i++) {
            if (activeAlarms[i].id === alarmId) {
                activeAlarms.splice(i, 1);
                activeAlarmsChanged();

                Logger.info("AlarmManager", "Alarm dismissed: " + alarmId);
                alarmDismissed(alarmId);

                // Re-schedule if repeating
                _rescheduleRepeatingAlarm(alarmId);

                return true;
            }
        }
        return false;
    }

    function getNextAlarmTime() {
        var now = new Date();
        var nextTime = null;
        var nextAlarm = null;

        for (var i = 0; i < alarms.length; i++) {
            if (!alarms[i].enabled)
                continue;
            var alarmTime = _calculateNextOccurrence(alarms[i], now);
            if (alarmTime && (!nextTime || alarmTime < nextTime)) {
                nextTime = alarmTime;
                nextAlarm = alarms[i];
            }
        }

        return nextTime;
    }

    function _calculateNextOccurrence(alarm, fromDate) {
        var parts = alarm.time.split(":");
        var hours = parseInt(parts[0]);
        var minutes = parseInt(parts[1]);

        var next = new Date(fromDate);
        next.setHours(hours, minutes, 0, 0);

        // If time has passed today, start from tomorrow
        if (next <= fromDate) {
            next.setDate(next.getDate() + 1);
        }

        // Handle repeating alarms
        if (alarm.repeat && alarm.repeat.length > 0) {
            // Find next occurrence on a repeat day
            var currentDay = next.getDay();
            var daysToAdd = 0;
            var found = false;

            for (var i = 0; i < 7; i++) {
                var checkDay = (currentDay + i) % 7;
                if (alarm.repeat.indexOf(checkDay) !== -1) {
                    daysToAdd = i;
                    found = true;
                    break;
                }
            }

            if (found) {
                next.setDate(next.getDate() + daysToAdd);
            } else {
                return null;  // No valid repeat day
            }
        }

        return next;
    }

    function _scheduleNextAlarm() {
        var nextTime = getNextAlarmTime();

        if (nextTime) {
            var now = new Date();
            var msUntil = nextTime - now;

            Logger.info("AlarmManager", "Next alarm in " + Math.round(msUntil / 1000 / 60) + " minutes");

            // In production, this would set a system wake alarm via:
            // - Linux: /sys/class/rtc/rtc0/wakealarm
            // - OR: systemd timer with WakeSystem=true
            if (typeof PowerManager !== 'undefined') {
                PowerManager.scheduleWake(nextTime, "alarm");
            }

            checkTimer.interval = Math.min(msUntil, 60000);  // Check at least every minute
            checkTimer.restart();
        } else {
            Logger.info("AlarmManager", "No alarms scheduled");
            checkTimer.stop();
        }
    }

    function _scheduleSnooze(alarm, minutes) {
        var snoozeTime = new Date();
        snoozeTime.setMinutes(snoozeTime.getMinutes() + minutes);

        if (typeof PowerManager !== 'undefined') {
            PowerManager.scheduleWake(snoozeTime, "alarm_snooze");
        }
    }

    function _rescheduleRepeatingAlarm(alarmId) {
        // If alarm is repeating, it will be caught in next _scheduleNextAlarm() call
        _scheduleNextAlarm();
    }

    function _checkAlarms() {
        var now = new Date();
        var currentTime = Qt.formatTime(now, "HH:mm");

        for (var i = 0; i < alarms.length; i++) {
            var alarm = alarms[i];
            if (!alarm.enabled)
                continue;

            // Check if this alarm should trigger now
            if (alarm.time === currentTime) {
                // Check day of week for repeating alarms
                if (alarm.repeat && alarm.repeat.length > 0) {
                    if (alarm.repeat.indexOf(now.getDay()) === -1) {
                        // Not scheduled for today
                        continue;
                    }
                }

                // Trigger alarm
                _triggerAlarm(alarm);
            }
        }
    }

    function _triggerAlarm(alarm) {
        Logger.info("AlarmManager", "ALARM TRIGGERED: " + alarm.label);

        // Add to active alarms
        activeAlarms.push(alarm);
        activeAlarmsChanged();

        // Wake the system
        if (typeof PowerManager !== 'undefined') {
            PowerManager.wake("alarm");
        }

        // Turn on screen
        if (typeof DisplayManager !== 'undefined') {
            DisplayManager.turnScreenOn();
        }

        // Play alarm sound
        if (alarm.sound && typeof AudioManager !== 'undefined') {
            AudioManager.playAlarmSound();
        }

        // Vibrate
        if (alarm.vibrate && typeof HapticService !== 'undefined') {
            HapticService.pattern([500, 200, 500, 200, 500]);  // Pattern
        }

        // Show alarm UI
        alarmTriggered(alarm);
    }

    function _saveAlarms() {
        var data = JSON.stringify(alarms);
        SettingsManagerCpp.set("alarms/data", data);
    }

    function _loadAlarms() {
        var data = SettingsManagerCpp.get("alarms/data", "[]");
        try {
            alarms = JSON.parse(data);
            Logger.info("AlarmManager", "Loaded " + alarms.length + " alarms");
        } catch (e) {
            Logger.error("AlarmManager", "Failed to load alarms: " + e);
            alarms = [];
        }
    }

    property var checkTimer: Timer {
        id: checkTimer
        repeat: true
        running: true
        interval: 60000
        onTriggered: {
            _checkAlarms();
            _scheduleNextAlarm();
        }
    }

    Component.onCompleted: {
        Logger.info("AlarmManager", "Initialized");
        _loadAlarms();
        _scheduleNextAlarm();
    }
}
