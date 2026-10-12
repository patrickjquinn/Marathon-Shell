import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "ClockLogic.js" as Logic
import "models"
import "pages"
import "cover"

ApplicationWindow {
    id: root

    readonly property var alarms: Alarms.alarms
    property var cities: Logic.parseCities(Settings.get("clock/worldCities", ""), Logic.defaultCities)
    property Stopwatch stopwatch: Stopwatch {
        ticking: Qt.application.state === Qt.ApplicationActive
    }
    property CountdownTimer countdown: CountdownTimer {
        onFinished: Alarms.triggerAlarmNow("Timer")
        onRunningChanged: root._holdBackground(running)
    }
    // Keeps the app from being frozen while a countdown runs.
    property int _backgroundTask: 0

    function _holdBackground(hold) {
        if (hold && _backgroundTask === 0)
            _backgroundTask = Lifecycle.beginBackgroundTask("countdown-timer", "timer running");
        else if (!hold && _backgroundTask !== 0) {
            Lifecycle.endBackgroundTask(_backgroundTask);
            _backgroundTask = 0;
        }
    }

    function _check(ok) {
        if (!ok)
            Notices.show(qsTr("Couldn't save the alarm. Try again."));
        return ok;
    }

    function editAlarm(alarm) {
        const now = new Date();
        const t = alarm ? Logic.parseTime(alarm.time) : { hour: now.getHours(), minute: now.getMinutes() };
        pageStack.push(Qt.resolvedUrl("pages/AlarmDialog.qml"), {
            app: root,
            alarmId: alarm ? alarm.id : "",
            hour: t.hour,
            minute: t.minute,
            label: alarm && alarm.label !== "Alarm" ? alarm.label : "",
            repeat: alarm && alarm.repeat ? alarm.repeat : []
        });
    }

    function _announce(time, repeat) {
        const now = new Date();
        const when = Logic.nextOccurrence({ enabled: true, time: time, repeat: repeat }, now);
        if (when)
            Notices.show(Logic.alarmIn(when, now));
    }

    function saveAlarm(id, hour, minute, label, repeat) {
        const time = Logic.timeString(hour, minute);
        const ok = id === ""
                ? _check(Alarms.createAlarm(time, label || qsTr("Alarm"), repeat, { vibrate: true, snoozeEnabled: true, snoozeDuration: 10 }) !== "")
                : _check(Alarms.updateAlarm(id, { time: time, label: label || qsTr("Alarm"), enabled: true, repeat: repeat }));
        if (ok)
            _announce(time, repeat);
        return ok;
    }

    function toggleAlarm(id) {
        const alarm = alarms.find(a => a.id === id);
        if (!alarm || !_check(Alarms.updateAlarm(id, { enabled: !alarm.enabled })))
            return false;
        if (!alarm.enabled)
            _announce(alarm.time, alarm.repeat || []);
        return true;
    }

    function deleteAlarm(id) {
        if (!Alarms.deleteAlarm(id))
            Notices.show(qsTr("Couldn't delete the alarm. Try again."));
    }

    function setTimer(seconds) {
        countdown.set(seconds);
        Settings.set("clock/lastTimer", seconds);
    }

    function _saveCities(next) {
        cities = next;
        Settings.set("clock/worldCities", JSON.stringify(next));
    }

    function addCity(city) {
        if (!cities.some(c => c.name === city.name))
            _saveCities(cities.concat([city]));
    }

    function removeCity(name) {
        _saveCities(cities.filter(c => c.name !== name));
    }

    function moveCity(from, to) {
        _saveCities(Logic.moveCity(cities, from, to));
    }

    function cityTime(city, now) {
        const tz = Logic.zoneFor(city, Logic.knownCities);
        if (tz) {
            const r = WorldClock.timeIn(tz);
            return { time: r.time, diff: r.offsetLabel, weekday: r.weekday };
        }
        return { time: Logic.offsetTime(city.offset, now), diff: (city.offset >= 0 ? "+" : "") + city.offset + "h", weekday: "" };
    }

    appId: "clock"
    cover: Component {
        ClockCover {
            alarms: root.alarms
            stopwatch: root.stopwatch
            countdown: root.countdown
            onNewAlarmRequested: {
                root.activate();
                root.editAlarm(null);
            }
        }
    }
    initialPage: Component {
        MainPage {
            app: root
        }
    }
}
