import QtQuick
import QtTest
import "../ClockLogic.js" as Logic

TestCase {
    name: "ClockLogic"

    function test_timeStrings() {
        compare(Logic.timeString(7, 5), "07:05");
        compare(Logic.timeString(23, 59), "23:59");
        compare(Logic.parseTime("07:30"), { hour: 7, minute: 30 });
        compare(Logic.parseTime(""), { hour: 0, minute: 0 });
    }

    function test_toggleDay() {
        compare(Logic.toggleDay([], 3), [3]);
        compare(Logic.toggleDay([5, 1], 3), [1, 3, 5]);
        compare(Logic.toggleDay([1, 3, 5], 3), [1, 5]);
    }

    function test_repeatSummary() {
        const name = d => ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d];
        compare(Logic.repeatSummary([], name), "");
        compare(Logic.repeatSummary([0, 1, 2, 3, 4, 5, 6], name), "Every day");
        compare(Logic.repeatSummary([5, 4, 3, 2, 1], name), "Weekdays");
        compare(Logic.repeatSummary([6, 0], name), "Weekends");
        compare(Logic.repeatSummary([0, 1, 3], name), "Mon Wed Sun");
    }

    // Wed 2026-10-14 08:00 local.
    readonly property var wed: new Date(2026, 9, 14, 8, 0, 0)

    function test_nextOccurrenceOneShot() {
        compare(Logic.nextOccurrence({ time: "09:15", enabled: true }, wed), new Date(2026, 9, 14, 9, 15));
        compare(Logic.nextOccurrence({ time: "07:00", enabled: true }, wed), new Date(2026, 9, 15, 7, 0));
        compare(Logic.nextOccurrence({ time: "08:00", enabled: true }, wed), new Date(2026, 9, 15, 8, 0));
        compare(Logic.nextOccurrence({ time: "09:15", enabled: false }, wed), null);
    }

    function test_nextOccurrenceRepeating() {
        // Mondays only: next is Mon 19th.
        compare(Logic.nextOccurrence({ time: "06:30", enabled: true, repeat: [1] }, wed), new Date(2026, 9, 19, 6, 30));
        // Wednesday, later today.
        compare(Logic.nextOccurrence({ time: "20:00", enabled: true, repeat: [3] }, wed), new Date(2026, 9, 14, 20, 0));
        // Wednesday, already passed: a week later.
        compare(Logic.nextOccurrence({ time: "07:00", enabled: true, repeat: [3] }, wed), new Date(2026, 9, 21, 7, 0));
    }

    function test_nextAlarm() {
        const alarms = [
            { id: "a", time: "07:00", enabled: true },
            { id: "b", time: "09:00", enabled: true },
            { id: "c", time: "08:30", enabled: false }
        ];
        const next = Logic.nextAlarm(alarms, wed);
        compare(next.alarm.id, "b");
        compare(next.when, new Date(2026, 9, 14, 9, 0));
        compare(Logic.nextAlarm([], wed), null);
        compare(Logic.nextAlarm([alarms[2]], wed), null);
    }

    function test_formatStopwatch() {
        compare(Logic.formatStopwatch(0), "00:00.00");
        compare(Logic.formatStopwatch(61234), "01:01.23");
        compare(Logic.formatStopwatch(3725990), "1:02:05.99");
    }

    function test_formatCountdown() {
        compare(Logic.formatCountdown(0), "0:00");
        compare(Logic.formatCountdown(65), "1:05");
        compare(Logic.formatCountdown(3725), "1:02:05");
    }

    readonly property var known: [{ name: "Tokyo", tz: "Asia/Tokyo", offset: 9 }]

    function test_parseCities() {
        compare(Logic.parseCities("", known), known);
        compare(Logic.parseCities("{bad", known), known);
        compare(Logic.parseCities("{\"a\":1}", known), known);
        compare(Logic.parseCities("[]", known), []);
        compare(Logic.parseCities("[{\"name\":\"Rome\",\"tz\":\"Europe/Rome\"}]", known)[0].name, "Rome");
    }

    function test_zoneFor() {
        compare(Logic.zoneFor({ name: "Rome", tz: "Europe/Rome" }, known), "Europe/Rome");
        compare(Logic.zoneFor({ name: "Tokyo", offset: 9 }, known), "Asia/Tokyo");
        compare(Logic.zoneFor({ name: "Nowhere", offset: 2 }, known), "");
    }

    function test_offsetTime() {
        compare(Logic.offsetTime(9, new Date(Date.UTC(2026, 0, 1, 3, 4))), "12:04 PM");
        compare(Logic.offsetTime(-5, new Date(Date.UTC(2026, 0, 1, 3, 4))), "10:04 PM");
    }

    function test_moveCity() {
        const c = [{ name: "a" }, { name: "b" }, { name: "c" }];
        compare(Logic.moveCity(c, 2, 0).map(x => x.name), ["c", "a", "b"]);
        compare(Logic.moveCity(c, 0, 1).map(x => x.name), ["b", "a", "c"]);
        compare(Logic.moveCity(c, 0, 5), c);
        compare(c.map(x => x.name), ["a", "b", "c"]);
    }

    function test_filterCities() {
        const all = [{ name: "Paris" }, { name: "São Paulo" }, { name: "Tokyo" }];
        compare(Logic.filterCities(all, "").length, 3);
        compare(Logic.filterCities(all, "pa").map(x => x.name), ["Paris", "São Paulo"]);
        compare(Logic.filterCities(all, "zz").length, 0);
    }
}
