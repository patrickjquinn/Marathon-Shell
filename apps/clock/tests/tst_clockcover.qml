import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"
import "../models"

TestCase {
    id: testCase

    name: "ClockCover"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: cover
        ClockCover {}
    }
    Component {
        id: stopwatch
        Stopwatch {}
    }
    Component {
        id: countdown
        CountdownTimer {}
    }
    SignalSpy {
        id: newSpy
        signalName: "newAlarmRequested"
    }

    function make(alarms) {
        const s = stopwatch.createObject(testCase);
        const c = countdown.createObject(testCase);
        const v = createTemporaryObject(cover, testCase, { alarms: alarms, stopwatch: s, countdown: c, now: new Date(2026, 9, 14, 8, 0) });
        return { cover: v, stopwatch: s, countdown: c };
    }

    function test_placeholderWithoutAlarms() {
        const t = make([]);
        compare(t.cover.mode, "idle");
        verify(findChild(t.cover, "coverPlaceholder").visible);
    }

    function test_nextAlarm() {
        const t = make([{ id: "a", time: "07:00", label: "Early", enabled: true }, { id: "b", time: "09:30", label: "Standup", enabled: true }]);
        compare(t.cover.mode, "alarm");
        verify(!findChild(t.cover, "coverPlaceholder").visible);
        compare(t.cover.next.alarm.id, "b");
        compare(findChild(t.cover, "coverSubtitle").text, "Standup");
    }

    function test_runningTimerWins() {
        const t = make([{ id: "a", time: "09:00", label: "", enabled: true }]);
        t.countdown.set(90);
        t.countdown.start();
        compare(t.cover.mode, "timer");
        compare(findChild(t.cover, "coverTitle").text, "1:30");
        const toggle = findChild(t.cover, "toggleTimer");
        compare(toggle.iconSource, "image://theme/icon-cover-pause");
        toggle.triggered();
        verify(!t.countdown.running);
    }

    function test_pausedTimerStaysAndResumes() {
        const t = make([{ id: "a", time: "09:00", label: "", enabled: true }]);
        t.countdown.set(90);
        t.countdown.start();
        t.countdown.pause();
        compare(t.cover.mode, "timer");
        compare(findChild(t.cover, "coverDetail").text, "Paused");
        const toggle = findChild(t.cover, "toggleTimer");
        compare(toggle.iconSource, "image://theme/icon-cover-play");
        toggle.triggered();
        verify(t.countdown.running);
        t.countdown.reset();
        compare(t.cover.mode, "alarm");
    }

    function test_runningStopwatch() {
        const t = make([]);
        t.stopwatch.start();
        compare(t.cover.mode, "stopwatch");
        findChild(t.cover, "stopStopwatch").triggered();
        verify(!t.stopwatch.running);
    }

    function test_newAlarmAction() {
        const t = make([]);
        newSpy.target = t.cover;
        newSpy.clear();
        findChild(t.cover, "newAlarmAction").triggered();
        compare(newSpy.count, 1);
    }
}
