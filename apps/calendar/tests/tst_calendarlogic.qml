import QtQuick
import QtTest
import "../CalendarLogic.js" as Logic

TestCase {
    name: "CalendarLogic"

    function test_dateKeys() {
        compare(Logic.dateKey(new Date(2026, 0, 5)), "2026-01-05");
        const d = Logic.parseDate("2026-10-12");
        compare(d.getFullYear(), 2026);
        compare(d.getMonth(), 9);
        compare(d.getDate(), 12);
        verify(isNaN(Logic.parseDate("").getTime()));
    }

    function test_times() {
        compare(Logic.timeString(7, 5), "07:05");
        compare(Logic.parseTime("09:30"), {
            hour: 9,
            minute: 30
        });
        compare(Logic.parseTime(""), {
            hour: 12,
            minute: 0
        });
    }

    function test_recurrence() {
        const base = {
            date: "2026-10-12",
            recurring: "none"
        };
        verify(Logic.occursOn(base, new Date(2026, 9, 12)));
        verify(!Logic.occursOn(base, new Date(2026, 9, 13)));
        const daily = Object.assign({}, base, {
            recurring: "daily"
        });
        verify(Logic.occursOn(daily, new Date(2027, 0, 1)));
        verify(!Logic.occursOn(daily, new Date(2026, 9, 11)));
        const weekly = Object.assign({}, base, {
            recurring: "weekly"
        });
        verify(Logic.occursOn(weekly, new Date(2026, 9, 26)));
        verify(Logic.occursOn(weekly, new Date(2026, 10, 2)));
        verify(!Logic.occursOn(weekly, new Date(2026, 9, 27)));
        const monthly = Object.assign({}, base, {
            recurring: "monthly"
        });
        verify(Logic.occursOn(monthly, new Date(2027, 2, 12)));
        verify(!Logic.occursOn(monthly, new Date(2026, 10, 13)));
    }

    function test_eventsOnSortsAllDayFirst() {
        const events = [
            {
                id: 1,
                date: "2026-10-12",
                time: "14:00"
            },
            {
                id: 2,
                date: "2026-10-12",
                time: "09:00"
            },
            {
                id: 3,
                date: "2026-10-12",
                time: "18:00",
                allDay: true
            },
            {
                id: 4,
                date: "2026-10-13",
                time: "08:00"
            }
        ];
        compare(Logic.eventsOn(events, new Date(2026, 9, 12)).map(e => e.id), [3, 2, 1]);
        compare(Logic.eventsOn(undefined, new Date()), []);
    }

    function test_sortedAndSearch() {
        const events = [
            {
                id: 1,
                date: "2026-11-01",
                time: "10:00",
                title: "Dentist"
            },
            {
                id: 2,
                date: "2026-10-01",
                time: "10:00",
                title: "Team lunch",
                description: "Pizza"
            },
            {
                id: 3,
                date: "2026-10-01",
                time: "08:00",
                title: "Gym"
            }
        ];
        compare(Logic.sorted(events).map(e => e.id), [3, 2, 1]);
        compare(Logic.search(events, "pizza").map(e => e.id), [2]);
        compare(Logic.search(events, " D ").map(e => e.id), [1]);
        compare(Logic.search(events, ""), []);
    }

    function test_upcoming() {
        const events = [
            {
                id: 1,
                date: "2026-10-12",
                time: "09:00"
            },
            {
                id: 2,
                date: "2026-10-12",
                time: "15:00"
            },
            {
                id: 3,
                date: "2026-10-12",
                time: "08:00",
                allDay: true
            },
            {
                id: 4,
                date: "2026-10-13",
                time: "15:00"
            }
        ];
        compare(Logic.upcoming(events, new Date(2026, 9, 12, 12, 0)).map(e => e.id), [3, 2]);
    }

    function test_endTimes() {
        compare(Logic.addMinutes("09:30", 60), "10:30");
        compare(Logic.addMinutes("23:30", 60), "00:30");
        compare(Logic.addMinutes("00:15", -30), "23:45");
        compare(Logic.duration("09:00", "10:30"), 90);
        compare(Logic.duration("23:00", "01:00"), 120);
        verify(Logic.endsNextDay({
            time: "23:00",
            endTime: "01:00"
        }));
        verify(!Logic.endsNextDay({
            time: "09:00",
            endTime: "10:00"
        }));
        verify(!Logic.endsNextDay({
            time: "09:00"
        }));
    }

    function test_upcomingKeepsEventsInProgress() {
        const events = [
            {
                id: 1,
                date: "2026-10-12",
                time: "11:00",
                endTime: "13:00"
            },
            {
                id: 2,
                date: "2026-10-12",
                time: "09:00",
                endTime: "10:00"
            },
            {
                id: 3,
                date: "2026-10-12",
                time: "23:00",
                endTime: "01:00"
            },
            {
                id: 4,
                date: "2026-10-12",
                time: "11:00"
            }
        ];
        compare(Logic.upcoming(events, new Date(2026, 9, 12, 12, 0)).map(e => e.id), [1, 3]);
    }

    function test_firstFrom() {
        const list = [
            {
                date: "2026-01-01"
            },
            {
                date: "2026-03-01"
            },
            {
                date: "2026-03-01"
            },
            {
                date: "2026-05-01"
            }
        ];
        compare(Logic.firstFrom(list, "2025-12-01"), 0);
        compare(Logic.firstFrom(list, "2026-03-01"), 1);
        compare(Logic.firstFrom(list, "2026-04-01"), 3);
        compare(Logic.firstFrom(list, "2027-01-01"), 3);
        compare(Logic.firstFrom([], "2027-01-01"), -1);
    }

    function test_searchMatchesLocation() {
        const events = [
            {
                id: 1,
                date: "2026-10-01",
                time: "10:00",
                title: "Lunch",
                location: "Café Nero"
            }
        ];
        compare(Logic.search(events, "nero").map(e => e.id), [1]);
    }
}
