import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "ClockApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent
        ClockApp {
            width: 540
            height: 1140
        }
    }

    function init() {
        Alarms.reset();
        Settings.values = {};
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        return app;
    }

    function tabsOf(app) {
        const tabs = app.pageStack.currentPage.tabs;
        tryVerify(() => tabs.currentItem !== null && tabs.currentItem.item !== null, 3000);
        return tabs;
    }

    function test_fourTabsAlarmsFirst() {
        const tabs = tabsOf(makeApp());
        compare(tabs.count, 4);
        compare(tabs.model.get(0).title, "Alarms");
        compare(tabs.model.get(1).title, "World clock");
        compare(tabs.model.get(2).title, "Stopwatch");
        compare(tabs.model.get(3).title, "Timer");
        compare(tabs.currentIndex, 0);
        verify(findChild(tabs, "alarmList") !== null);
    }

    function test_switchTabs() {
        const tabs = tabsOf(makeApp());
        tabs.moveTo(2, PagedView.Immediate);
        tryCompare(tabs, "currentIndex", 2);
        tryVerify(() => findChild(tabs.currentItem, "stopwatchTime") !== null, 3000);
        tabs.moveTo(3, PagedView.Immediate);
        tryCompare(tabs, "currentIndex", 3);
        tryVerify(() => findChild(tabs.currentItem, "timerTime") !== null, 3000);
        tabs.moveTo(1, PagedView.Immediate);
        tryVerify(() => findChild(tabs.currentItem, "cityList") !== null, 3000);
        tryCompare(findChild(tabs.currentItem, "cityList"), "count", 4);
    }

    function test_createAndEditAlarm() {
        const app = makeApp();
        verify(app.saveAlarm("", 6, 45, "", [1, 2]));
        compare(app.alarms.length, 1);
        compare(app.alarms[0].time, "06:45");
        compare(app.alarms[0].label, "Alarm");
        compare(app.alarms[0].repeat, [1, 2]);
        const id = app.alarms[0].id;
        verify(app.saveAlarm(id, 7, 0, "Gym", []));
        compare(app.alarms[0].time, "07:00");
        compare(app.alarms[0].label, "Gym");
    }

    function test_toggleAndDelete() {
        const app = makeApp();
        app.saveAlarm("", 6, 45, "", []);
        const id = app.alarms[0].id;
        verify(app.toggleAlarm(id));
        verify(!app.alarms[0].enabled);
        verify(app.toggleAlarm(id));
        verify(app.alarms[0].enabled);
        verify(!app.toggleAlarm("missing"));
        app.deleteAlarm(id);
        compare(app.alarms.length, 0);
    }

    function test_backendFailureReported() {
        const app = makeApp();
        Alarms.fail = true;
        verify(!app.saveAlarm("", 6, 45, "", []));
    }

    function test_editAlarmOpensDialog() {
        const app = makeApp();
        app.saveAlarm("", 7, 30, "Gym", [3]);
        app.editAlarm(app.alarms[0]);
        const dialog = app.pageStack.currentPage;
        tryCompare(dialog, "status", PageStatus.Active);
        compare(dialog.alarmId, app.alarms[0].id);
        compare(dialog.hour, 7);
        compare(dialog.minute, 30);
        compare(dialog.label, "Gym");
        compare(dialog.repeat, [3]);
        dialog.hour = 8;
        dialog.accept();
        tryCompare(app.alarms[0], "time", "08:30");
    }

    function test_newAlarmDialogStartsNow() {
        const app = makeApp();
        app.editAlarm(null);
        const dialog = app.pageStack.currentPage;
        compare(dialog.alarmId, "");
        compare(dialog.hour, new Date().getHours());
        compare(dialog.label, "");
    }

    function test_citiesPersist() {
        const app = makeApp();
        compare(app.cities.map(c => c.name), ["New York", "London", "Tokyo", "Sydney"]);
        app.addCity({ name: "Rome", tz: "Europe/Rome", offset: 1 });
        app.addCity({ name: "Rome", tz: "Europe/Rome", offset: 1 });
        compare(app.cities.length, 5);
        app.moveCity(4, 0);
        app.removeCity("London");
        compare(JSON.parse(Settings.get("clock/worldCities", "")).map(c => c.name), ["Rome", "New York", "Tokyo", "Sydney"]);
        compare(createTemporaryObject(appComponent, testCase).cities.length, 4);
    }

    function test_cityTime() {
        const app = makeApp();
        compare(app.cityTime({ name: "London", tz: "Europe/London" }, new Date()).diff, "Local");
        const legacy = app.cityTime({ name: "Atlantis", offset: -3 }, new Date(Date.UTC(2026, 0, 1, 12, 0)));
        compare(legacy.time, "9:00 AM");
        compare(legacy.diff, "-3h");
    }

    function test_countdownHoldsBackgroundAndRings() {
        const app = makeApp();
        const held = Lifecycle.held;
        app.countdown.set(1);
        app.countdown.start();
        compare(Lifecycle.held, held + 1);
        tryCompare(Alarms, "triggered", ["Timer"], 3000);
        compare(Lifecycle.held, held);
    }

    function test_timerTabControls() {
        const app = makeApp();
        const tabs = tabsOf(app);
        tabs.moveTo(3, PagedView.Immediate);
        let presets = null;
        tryVerify(() => (presets = findChild(tabs.currentItem, "presets")) !== null, 3000);
        presets.itemAt(2).clicked(null);
        compare(app.countdown.remaining, 300);
        findChild(tabs.currentItem, "startPause").clicked(null);
        verify(app.countdown.running);
        compare(findChild(tabs.currentItem, "timerTime").text, "5:00");
        findChild(tabs.currentItem, "reset").clicked(null);
        verify(!app.countdown.running);
        compare(app.countdown.remaining, 0);
    }

    function test_stopwatchTabControls() {
        const app = makeApp();
        const tabs = tabsOf(app);
        tabs.moveTo(2, PagedView.Immediate);
        let start = null;
        tryVerify(() => (start = findChild(tabs.currentItem, "startStop")) !== null, 3000);
        const lapReset = findChild(tabs.currentItem, "lapReset");
        verify(!lapReset.enabled);
        start.clicked(null);
        verify(app.stopwatch.running);
        compare(lapReset.text, "Lap");
        wait(50);
        lapReset.clicked(null);
        compare(app.stopwatch.laps.length, 1);
        start.clicked(null);
        verify(!app.stopwatch.running);
        compare(lapReset.text, "Reset");
        lapReset.clicked(null);
        compare(app.stopwatch.elapsed, 0);
        compare(app.stopwatch.laps.length, 0);
    }
}
