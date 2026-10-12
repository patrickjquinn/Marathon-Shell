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

    function test_offsetDate() {
        const tokyo = Logic.offsetDate(9, new Date(Date.UTC(2026, 0, 1, 3, 4)));
        compare([tokyo.getHours(), tokyo.getMinutes(), tokyo.getDate()], [12, 4, 1]);
        const ny = Logic.offsetDate(-5, new Date(Date.UTC(2026, 0, 1, 3, 4)));
        compare([ny.getHours(), ny.getMinutes(), ny.getDate()], [22, 4, 31]);
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

    function test_filterCitiesByCountryAfterName() {
        const all = [{ name: "Cork", country: "Ireland" }, { name: "Irkutsk", country: "Russia" }, { name: "Paris", country: "France" }];
        compare(Logic.filterCities(all, "ir").map(x => x.name), ["Irkutsk", "Cork"]);
        compare(Logic.filterCities(all, "  ireland ").map(x => x.name), ["Cork"]);
    }

    function test_knownCitiesComeFromTzdata_data() {
        return ["Dublin", "Lisbon", "Cairo", "Lagos", "Jakarta", "New York", "Beijing", "Mumbai"].map(n => ({ tag: n, name: n }));
    }

    function test_knownCitiesComeFromTzdata(data) {
        const city = Logic.knownCities.find(c => c.name === data.name);
        verify(city, data.name);
        verify(city.tz.indexOf("/") > 0);
        verify(city.country !== "");
    }

    function test_defaultCitiesAreKnown() {
        compare(Logic.defaultCities.map(c => c.tz), ["America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"]);
    }

    function test_alarmIn_data() {
        const now = new Date(2026, 0, 5, 23, 40, 10);
        const at = (d, h, m) => new Date(2026, 0, d, h, m);
        return [
            { tag: "hours and minutes", when: at(6, 7, 0), now: now, out: "Alarm in 7 h 20 min" },
            { tag: "minutes", when: at(6, 0, 5), now: now, out: "Alarm in 25 min" },
            { tag: "exact hours", when: at(6, 1, 40), now: new Date(2026, 0, 5, 23, 40), out: "Alarm in 2 h" },
            { tag: "under a minute", when: at(5, 23, 41), now: now, out: "Alarm in less than a minute" },
            { tag: "days", when: at(8, 7, 0), now: now, out: "Alarm in 2 d 7 h" }
        ];
    }

    function test_alarmIn(data) {
        compare(Logic.alarmIn(data.when, data.now), data.out);
    }

    function test_lapSplits() {
        compare(Logic.lapSplits([]), []);
        compare(Logic.lapSplits([1130, 2377, 3000]), [1130, 1247, 623]);
    }
}
