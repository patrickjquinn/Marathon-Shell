import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    id: testCase

    name: "CalendarCover"
    when: windowShown
    visible: true
    width: 270
    height: 420

    Component {
        id: coverComponent
        CalendarCover {
            width: 270
            height: 420
        }
    }

    SignalSpy {
        id: spy
    }

    function test_showsTodaysNextEvents() {
        const now = new Date(2026, 9, 12, 12, 0);
        const cover = createTemporaryObject(coverComponent, testCase, {
            now: now,
            events: [
                {
                    id: 1,
                    title: "Earlier",
                    date: "2026-10-12",
                    time: "09:00"
                },
                {
                    id: 2,
                    title: "Later",
                    date: "2026-10-12",
                    time: "15:00"
                },
                {
                    id: 3,
                    title: "Holiday",
                    date: "2026-10-12",
                    time: "00:00",
                    allDay: true
                },
                {
                    id: 4,
                    title: "Tomorrow",
                    date: "2026-10-13",
                    time: "15:00"
                }
            ]
        });
        compare(cover.next.map(e => e.id), [3, 2]);
        compare(findChild(cover, "coverTitle").text, "Holiday");
        compare(findChild(cover, "coverTime").text, "All day");
        compare(findChild(cover, "coverEvents").count, 2);
        verify(!findChild(cover, "coverMore").visible);
        cover.events = cover.events.concat([
            {
                id: 5,
                title: "Late",
                date: "2026-10-12",
                time: "20:00"
            }
        ]);
        compare(findChild(cover, "coverMore").text, "1 more today");
        compare(findChild(cover, "coverDay").text, "12");
        verify(!findChild(cover, "coverEmpty").visible);
    }

    function test_emptyAndAction() {
        const cover = createTemporaryObject(coverComponent, testCase, {
            events: []
        });
        verify(findChild(cover, "coverEmpty").visible);
        compare(findChild(cover, "coverEvents").count, 0);
        spy.target = cover;
        spy.signalName = "newEventRequested";
        findChild(cover, "newEventAction").triggered();
        compare(spy.count, 1);
    }
}
