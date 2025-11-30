import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation
import "pages"

MApp {
    id: clockApp
    appId: "clock"
    appName: "Clock"
    // appIcon loaded from registry - don't override here

    property var alarms  // No initial binding - set by loadAlarms()
    property int nextAlarmId: 1

    Component.onCompleted: {
        loadAlarms();
    }

    function loadAlarms() {
        if (typeof AlarmManager !== 'undefined') {
            alarms = AlarmManager.alarms;
        } else {
            var savedAlarms = SettingsManagerCpp.get("clock/alarms", "[]");
            try {
                alarms = JSON.parse(savedAlarms);
                if (alarms.length > 0) {
                    nextAlarmId = Math.max(...alarms.map(a => parseInt(a.id) || 0)) + 1;
                }
            } catch (e) {
                Logger.error("ClockApp", "Failed to load alarms: " + e);
                alarms = [];  // Fallback to empty array on error
            }
        }
        alarmsChanged();
    }

    function saveAlarms() {
        var data = JSON.stringify(alarms);
        SettingsManagerCpp.set("clock/alarms", data);
    }

    function createAlarm(hour, minute, label, enabled) {
        var timeString = _padZero(hour) + ":" + _padZero(minute);
        var repeat = [];

        if (typeof AlarmManager !== 'undefined') {
            var alarmId = AlarmManager.createAlarm(timeString, label, repeat, {
                vibrate: true,
                snoozeEnabled: true,
                snoozeDuration: 10
            });

            loadAlarms();
            return {
                id: alarmId,
                hour: hour,
                minute: minute,
                label: label,
                enabled: true,
                repeat: repeat
            };
        } else {
            var alarm = {
                id: String(nextAlarmId++),
                time: timeString,
                hour: hour,
                minute: minute,
                label: label || "Alarm",
                enabled: enabled !== undefined ? enabled : true,
                repeat: []
            };
            alarms.push(alarm);
            alarmsChanged();
            saveAlarms();
            return alarm;
        }
    }

    function updateAlarm(id, hour, minute, label, enabled, repeat) {
        var timeString = _padZero(hour) + ":" + _padZero(minute);

        if (typeof AlarmManager !== 'undefined') {
            var repeatDays = [];
            if (repeat) {
                for (var i = 0; i < repeat.length; i++) {
                    if (repeat[i]) {
                        repeatDays.push(i);
                    }
                }
            }

            AlarmManager.updateAlarm(id, {
                time: timeString,
                label: label,
                enabled: enabled,
                repeat: repeatDays
            });

            loadAlarms();
        } else {
            for (var i = 0; i < alarms.length; i++) {
                if (alarms[i].id === id) {
                    alarms[i].time = timeString;
                    alarms[i].hour = hour;
                    alarms[i].minute = minute;
                    alarms[i].label = label;
                    alarms[i].enabled = enabled;
                    if (repeat)
                        alarms[i].repeat = repeat;
                    alarmsChanged();
                    saveAlarms();
                    return true;
                }
            }
        }
        return true;
    }

    function deleteAlarm(id) {
        if (typeof AlarmManager !== 'undefined') {
            AlarmManager.deleteAlarm(id);
            loadAlarms();
        } else {
            for (var i = 0; i < alarms.length; i++) {
                if (alarms[i].id === id) {
                    alarms.splice(i, 1);
                    alarmsChanged();
                    saveAlarms();
                    return true;
                }
            }
        }
        return true;
    }

    function toggleAlarm(id) {
        if (typeof AlarmManager !== 'undefined') {
            AlarmManager.toggleAlarm(id);
            loadAlarms();
        } else {
            for (var i = 0; i < alarms.length; i++) {
                if (alarms[i].id === id) {
                    alarms[i].enabled = !alarms[i].enabled;
                    alarmsChanged();
                    saveAlarms();
                    return true;
                }
            }
        }
        return true;
    }

    function _padZero(num) {
        return (num < 10 ? "0" : "") + num;
    }

    Connections {
        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null
        enabled: typeof AlarmManager !== 'undefined'

        function onAlarmCreated() {
            loadAlarms();
        }

        function onAlarmUpdated() {
            loadAlarms();
        }

        function onAlarmDeleted() {
            loadAlarms();
        }
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            anchors.fill: parent
            spacing: 0

            property int currentView: 0

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentView

                ClockPage {
                    id: clockPage
                }

                WorldClockPage {
                    id: worldClockPage
                }

                AlarmPage {
                    id: alarmPage
                }

                TimerPage {
                    id: timerPage
                }

                StopwatchPage {
                    id: stopwatchPage
                }
            }

            MTabBar {
                id: tabBar
                width: parent.width

                tabs: [
                    {
                        label: "Clock",
                        icon: "clock"
                    },
                    {
                        label: "World",
                        icon: "globe"
                    },
                    {
                        label: "Alarm",
                        icon: "bell"
                    },
                    {
                        label: "Timer",
                        icon: "timer"
                    },
                    {
                        label: "Stopwatch",
                        icon: "stopwatch"
                    }
                ]

                onTabSelected: index => {
                    HapticService.light();
                    parent.currentView = index;
                }
            }
        }
    }
}
