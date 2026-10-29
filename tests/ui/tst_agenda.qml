import QtQuick
import QtTest
import "../../shell/qml/core/Agenda.js" as Agenda

TestCase {
    name: "Agenda"

    readonly property var events: [
        {
            id: 1,
            title: "Standup",
            date: "2026-10-12",
            time: "09:30",
            allDay: false,
            recurring: "none"
        },
        {
            id: 2,
            title: "Gym",
            date: "2026-10-05",
            time: "18:00",
            allDay: false,
            recurring: "weekly"
        },
        {
            id: 3,
            title: "Holiday",
            date: "2026-10-12",
            time: "",
            allDay: true,
            recurring: "none"
        },
        {
            id: 4,
            title: "Rent",
            date: "2026-09-12",
            time: "08:00",
            allDay: false,
            recurring: "monthly"
        },
        {
            id: 5,
            title: "Pills",
            date: "2026-10-01",
            time: "07:00",
            allDay: false,
            recurring: "daily"
        },
        {
            id: 6,
            title: "Tomorrow",
            date: "2026-10-13",
            time: "10:00",
            allDay: false,
            recurring: "none"
        },
        {
            id: 7,
            title: "Future daily",
            date: "2026-10-20",
            time: "07:00",
            allDay: false,
            recurring: "daily"
        }
    ]

    function test_todaysEventsInOrder() {
        const day = Agenda.forDay(events, new Date(2026, 9, 12));
        compare(day.map(e => e.title), ["Holiday", "Pills", "Rent", "Standup", "Gym"]);
    }

    function test_emptyDay() {
        compare(Agenda.forDay([], new Date(2026, 9, 12)).length, 0);
        compare(Agenda.forDay(undefined, new Date(2026, 9, 12)).length, 0);
    }
}
