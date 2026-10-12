pragma ComponentBehavior: Bound
import MarathonApp.Clock
import MarathonOS.Shell
import MarathonUI.Containers
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

    function createAlarm(hour, minute, label, repeat) {
        if (typeof AlarmService === 'undefined')
            return false;

        var alarmId = AlarmService.createAlarm(_padZero(hour) + ":" + _padZero(minute), label, repeat, {
            "vibrate": true,
            "snoozeEnabled": true,
            "snoozeDuration": 10
        });
        loadAlarms();
        return alarmId !== "";
    }

    function updateAlarm(id, hour, minute, label, repeat) {
        if (typeof AlarmService === 'undefined')
            return false;

        var ok = AlarmService.updateAlarm(id, {
            "time": _padZero(hour) + ":" + _padZero(minute),
            "label": label || "Alarm",
            "enabled": true,
            "repeat": repeat
        });
        loadAlarms();
        return ok;
    }

    function deleteAlarm(id) {
        if (typeof AlarmService === 'undefined')
            return false;

        var ok = AlarmService.deleteAlarm(id);
        loadAlarms();
        return ok;
    }

    function restoreAlarm(alarm) {
        if (typeof AlarmService === 'undefined')
            return false;

        var alarmId = AlarmService.createAlarm(alarm.time, alarm.label, alarm.repeat || [], {
            "sound": alarm.sound,
            "vibrate": alarm.vibrate,
            "snoozeEnabled": alarm.snoozeEnabled,
            "snoozeDuration": alarm.snoozeDuration
        });
        if (alarmId !== "" && !alarm.enabled)
            AlarmService.updateAlarm(alarmId, {
                "enabled": false
            });
        loadAlarms();
        return alarmId !== "";
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
            clockApp.loadAlarms();
        }

        target: typeof AlarmService !== 'undefined' ? AlarmService : null
        enabled: typeof AlarmService !== 'undefined'
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Binding {
            target: clockApp
            property: "navigationDepth"
            value: alarmPage.backLayers + worldClockPage.backLayers
        }

        Connections {
            function onBackPressed() {
                if (alarmPage.backLayers > 0)
                    alarmPage.handleBack();
                else if (worldClockPage.backLayers > 0)
                    worldClockPage.handleBack();
            }

            target: clockApp
        }

        Column {
            property int currentView: 1     // default to Clock pane (index 1)

            anchors.fill: parent
            spacing: 0

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentView

                // Index order MUST match the tab labels in MTabBar below.
                WorldClockPage {
                    id: worldClockPage
                }

                ClockPage {
                    id: clockPage
                }

                AlarmPage {
                    id: alarmPage

                    app: clockApp
                }

                StopwatchPage {
                    id: stopwatchPage
                }

                TimerPage {
                    id: timerPage
                }
            }

            MTabBar {
                id: tabBar

                width: parent.width
                activeTab: parent.currentView
                tabs: [
                    {
                        "label": "World",
                        "icon": "globe"
                    },
                    {
                        "label": "Clock",
                        "icon": "clock"
                    },
                    {
                        "label": "Alarm",
                        "icon": "bell"
                    },
                    {
                        "label": "Stopwatch",
                        "icon": "timer"
                    },
                    {
                        "label": "Timer",
                        "icon": "hourglass"
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
