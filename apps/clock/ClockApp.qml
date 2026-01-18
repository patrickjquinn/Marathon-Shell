import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

MApp {
    id: clockApp

    property var alarms: []

    function loadAlarms() {
        if (typeof AlarmService === 'undefined')
            return;

        alarms = AlarmService.alarms;
        alarmsChanged();
    }

    function createAlarm(hour, minute, label, enabled) {
        if (typeof AlarmService === 'undefined')
            return null;

        var timeString = _padZero(hour) + ":" + _padZero(minute);
        var repeat = [];
        var alarmId = AlarmService.createAlarm(timeString, label, repeat, {
            "vibrate": true,
            "snoozeEnabled": true,
            "snoozeDuration": 10
        });
        loadAlarms();
        return {
            "id": alarmId,
            "hour": hour,
            "minute": minute,
            "label": label,
            "enabled": enabled !== undefined ? enabled : true,
            "repeat": repeat
        };
    }

    function updateAlarm(id, hour, minute, label, enabled, repeat) {
        if (typeof AlarmService === 'undefined')
            return false;

        var timeString = _padZero(hour) + ":" + _padZero(minute);
        var repeatDays = [];
        if (repeat) {
            for (var i = 0; i < repeat.length; i++) {
                if (repeat[i])
                    repeatDays.push(i);
            }
        }
        AlarmService.updateAlarm(id, {
            "time": timeString,
            "label": label,
            "enabled": enabled,
            "repeat": repeatDays
        });
        loadAlarms();
        return true;
    }

    function deleteAlarm(id) {
        if (typeof AlarmService === 'undefined')
            return false;

        AlarmService.deleteAlarm(id);
        loadAlarms();
        return true;
    }

    function toggleAlarm(id) {
        if (typeof AlarmService === 'undefined')
            return false;

        var alarm = _getAlarmById(id);
        if (!alarm)
            return false;

        AlarmService.updateAlarm(id, {
            "enabled": !alarm.enabled
        });
        loadAlarms();
        return true;
    }

    function _padZero(num) {
        return (num < 10 ? "0" : "") + num;
    }

    function _getAlarmById(id) {
        if (!alarms)
            return null;
        for (var i = 0; i < alarms.length; i++) {
            if (alarms[i].id === id)
                return alarms[i];
        }
        return null;
    }

    appId: "clock"
    appName: "Clock"
    Component.onCompleted: {
        loadAlarms();
    }

    Connections {
        function onAlarmsChanged() {
            loadAlarms();
        }

        target: typeof AlarmService !== 'undefined' ? AlarmService : null
        enabled: typeof AlarmService !== 'undefined'
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            property int currentView: 0

            anchors.fill: parent
            spacing: 0

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
                        "label": "Clock",
                        "icon": "clock"
                    },
                    {
                        "label": "World",
                        "icon": "globe"
                    },
                    {
                        "label": "Alarm",
                        "icon": "bell"
                    },
                    {
                        "label": "Timer",
                        "icon": "timer"
                    },
                    {
                        "label": "Stopwatch",
                        "icon": "watch"
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
