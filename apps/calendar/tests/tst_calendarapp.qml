import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../CalendarLogic.js" as Logic
import ".."

TestCase {
    id: testCase

    name: "CalendarApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent
        CalendarApp {
            width: 540
            height: 1140
        }
    }

    readonly property string todayKey: Logic.dateKey(new Date())

    function ev(id, extra) {
        return Object.assign({ id: id, title: "Event " + id, date: todayKey, time: "10:00", allDay: false, recurring: "none", description: "" }, extra || {});
    }

    function makeApp(events) {
        Calendar.reset(events);
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null && !app.pageStack.busy);
        return app;
    }

    function pushed(app, depth) {
        tryCompare(app.pageStack, "depth", depth);
        tryVerify(() => !app.pageStack.busy);
        return app.pageStack.currentPage;
    }

    function child(item, name) {
        let found = null;
        tryVerify(() => (found = findChild(item, name)) !== null, 3000, name);
        return found;
    }

    function test_monthListsTheDaysEvents() {
        const app = makeApp([ev(1, { time: "15:00" }), ev(2, { allDay: true }), ev(3, { date: "2001-01-01" })]);
        const page = app.pageStack.currentPage;
        compare(page.dayEvents.map(e => e.id), [2, 1]);
        compare(child(page, "dayEvents").count, 2);
        verify(!child(page, "noEvents").visible);
        compare(child(page, "dayHeader").text, "Today");
        compare(child(page, "monthHeader").title, Qt.locale().standaloneMonthName(new Date().getMonth()));
    }

    function test_selectingADay() {
        const app = makeApp([ev(1, { date: "2026-03-14" })]);
        const page = app.pageStack.currentPage;
        page.showDate(new Date(2026, 2, 14));
        compare(page.dayEvents.length, 1);
        verify(!page.showingToday);
        page.showDate(new Date(2026, 2, 15));
        compare(page.dayEvents.length, 0);
        verify(child(page, "noEvents").visible);
    }

    function test_dayCellsMarkEvents() {
        const app = makeApp([ev(1)]);
        const picker = child(app.pageStack.currentPage, "datePicker");
        let dots = [];
        tryVerify(() => {
            dots = [];
            const walk = item => {
                for (let i = 0; i < item.children.length; ++i) {
                    const c = item.children[i];
                    if (c.objectName === "eventDot" && c.visible)
                        dots.push(c);
                    walk(c);
                }
            };
            walk(picker);
            return dots.length > 0;
        }, 3000);
        const cell = dots[0].parent;
        compare(cell.eventCount, 1);
        verify(cell.Accessible.name.indexOf("1 event") !== -1);
    }

    function test_createEvent() {
        const app = makeApp([]);
        const dialog = app.newEvent(new Date(2026, 4, 2));
        tryCompare(dialog, "status", PageStatus.Active);
        verify(!dialog.canAccept);
        dialog.title = "  Dentist ";
        dialog.hour = 9;
        dialog.minute = 15;
        dialog.reminder = 30;
        dialog.recurring = "weekly";
        verify(dialog.canAccept);
        dialog.accept();
        tryCompare(Calendar.events, "length", 1);
        const e = Calendar.events[0];
        compare(e.title, "Dentist");
        compare(e.date, "2026-05-02");
        compare(e.time, "09:15");
        compare(e.reminder, 30);
        compare(e.recurring, "weekly");
        compare(e.allDay, false);
        compare(e.endTime, "10:15");
        compare(e.location, "");
    }

    function test_newEventEndsAnHourLater() {
        const app = makeApp([]);
        const dialog = app.newEvent(new Date(2026, 4, 2));
        tryCompare(dialog, "status", PageStatus.Active);
        compare(Logic.duration(Logic.timeString(dialog.hour, dialog.minute), Logic.timeString(dialog.endHour, dialog.endMinute)), 60);
        verify(child(dialog, "endTimeButton").visible);
        child(dialog, "allDaySwitch").checked = true;
        verify(!child(dialog, "endTimeButton").visible);
    }

    function test_movingStartMovesEnd() {
        const app = makeApp([]);
        const dialog = app.newEvent(new Date(2026, 4, 2));
        tryCompare(dialog, "status", PageStatus.Active);
        dialog.hour = 9;
        dialog.minute = 0;
        dialog.setEnd(10, 30);
        dialog.hour = 14;
        dialog.minute = 15;
        compare(dialog.endHour, 15);
        compare(dialog.endMinute, 45);
        dialog.hour = 23;
        compare(child(dialog, "endTimeButton").value.indexOf("next day") !== -1, true);
    }

    function test_locationAndEndAreSavedAndShown() {
        const app = makeApp([]);
        const dialog = app.newEvent(new Date(2026, 4, 2));
        tryCompare(dialog, "status", PageStatus.Active);
        dialog.title = "Dentist";
        dialog.location = " 12 High St ";
        dialog.hour = 9;
        dialog.minute = 0;
        dialog.setEnd(9, 45);
        dialog.accept();
        tryCompare(Calendar.events, "length", 1);
        const e = Calendar.events[0];
        compare(e.time, "09:00");
        compare(e.endTime, "09:45");
        compare(e.location, "12 High St");
        pushed(app, 1);
        const page = app.openEvent(e);
        pushed(app, 2);
        compare(child(page, "timeDetail").value, app.timeRangeText(e));
        verify(child(page, "timeDetail").value.indexOf(app.timeText(e)) === 0);
        verify(child(page, "locationDetail").visible);
        compare(child(page, "locationDetail").value, "12 High St");
    }

    function test_editEventLoadsEndAndLocation() {
        const app = makeApp([ev(7, { time: "07:30", endTime: "08:15", location: "Gym" })]);
        const dialog = app.editEvent(Calendar.events[0]);
        tryCompare(dialog, "status", PageStatus.Active);
        compare(dialog.endHour, 8);
        compare(dialog.endMinute, 15);
        compare(dialog.location, "Gym");
    }

    function test_legacyEventWithoutEndShowsStartOnly() {
        const app = makeApp([ev(4)]);
        compare(app.timeRangeText(Calendar.events[0]), app.timeText(Calendar.events[0]));
        const dialog = app.editEvent(Calendar.events[0]);
        tryCompare(dialog, "status", PageStatus.Active);
        compare(dialog.endHour, 11);
        compare(dialog.endMinute, 0);
    }

    function test_editEventKeepsIdAndFields() {
        const app = makeApp([ev(7, { title: "Gym", time: "07:30", reminder: 15, description: "Legs", extra: "kept" })]);
        const dialog = app.editEvent(Calendar.events[0]);
        tryCompare(dialog, "status", PageStatus.Active);
        compare(dialog.title, "Gym");
        compare(dialog.hour, 7);
        compare(dialog.minute, 30);
        compare(dialog.reminder, 15);
        compare(dialog.description, "Legs");
        compare(child(dialog, "reminderBox").currentIndex, Logic.reminderMinutes.indexOf(15));
        dialog.allDay = true;
        dialog.accept();
        tryCompare(Calendar.events[0], "allDay", true);
        compare(Calendar.events[0].id, 7);
        compare(Calendar.events[0].extra, "kept");
    }

    function test_comboBoxesSetValues() {
        const app = makeApp([]);
        const dialog = app.newEvent(new Date());
        tryCompare(dialog, "status", PageStatus.Active);
        const repeat = child(dialog, "repeatBox");
        compare(repeat.value, "Never");
        repeat.currentIndex = 3;
        compare(dialog.recurring, "monthly");
        compare(repeat.value, "Every month");
        const reminder = child(dialog, "reminderBox");
        compare(reminder.value, "At time of event");
        reminder.currentIndex = 0;
        compare(dialog.reminder, -1);
        verify(child(dialog, "timeButton").visible);
        child(dialog, "allDaySwitch").checked = true;
        verify(!child(dialog, "timeButton").visible);
    }

    function test_saveFailureKeepsEvents() {
        const app = makeApp([ev(1)]);
        Calendar.fail = true;
        verify(!app.saveEvent({ title: "x", date: todayKey }));
        verify(!app.saveEvent(ev(1, { title: "y" })));
        verify(!app.deleteEvent(1));
        compare(Calendar.events.length, 1);
    }

    function test_eventPage() {
        const app = makeApp([ev(4, { title: "Review", recurring: "daily", reminder: 60, description: "Bring notes" })]);
        const page = app.openEvent(Calendar.events[0]);
        pushed(app, 2);
        compare(child(page, "eventHeader").title, "Review");
        compare(child(page, "timeDetail").value, app.timeRangeText(Calendar.events[0]));
        verify(!child(page, "locationDetail").visible);
        verify(child(page, "repeatDetail").visible);
        compare(child(page, "repeatDetail").value, "Every day");
        compare(child(page, "reminderDetail").value, "1 hour before");
        compare(child(page, "description").text, "Bring notes");
        Calendar.updateEvent(ev(4, { title: "Renamed" }));
        compare(child(page, "eventHeader").title, "Renamed");
        verify(!child(page, "repeatDetail").visible);
    }

    function test_eventPageDeleteWithRemorse() {
        const app = makeApp([ev(4)]);
        const page = app.openEvent(Calendar.events[0]);
        pushed(app, 2);
        page.remove();
        const remorse = child(page, "remorse");
        verify(remorse.active);
        compare(Calendar.events.length, 1);
        remorse.trigger();
        compare(Calendar.events.length, 0);
        pushed(app, 1);
    }

    function test_eventPageEdit() {
        const app = makeApp([ev(4)]);
        app.openEvent(Calendar.events[0]);
        pushed(app, 2);
        const dialog = app.editEvent(Calendar.events[0]);
        pushed(app, 3);
        dialog.title = "Changed";
        dialog.accept();
        pushed(app, 2);
        compare(child(app.pageStack.currentPage, "eventHeader").title, "Changed");
    }

    function test_yearPagePicksMonth() {
        const app = makeApp([]);
        const month = app.pageStack.currentPage;
        const year = month.openYear();
        pushed(app, 2);
        compare(child(year, "yearHeader").title, String(new Date().getFullYear()));
        compare(child(year, "months").count, 12);
        year.year = 2030;
        year.monthChosen(2030, 6);
        pushed(app, 1);
        compare(month.date.getFullYear(), 2030);
        compare(month.date.getMonth(), 6);
        compare(month.date.getDate(), 1);
    }

    function test_agendaPage() {
        const app = makeApp([ev(1, { date: "2026-12-01" }), ev(2, { date: "2026-01-01" }), ev(3, { date: "2026-01-01", time: "08:00" })]);
        const page = app.pageStack.push(Qt.resolvedUrl("../pages/AgendaPage.qml"), { app: app }, PageStackAction.Immediate);
        compare(page.shown.map(e => e.id), [3, 2, 1]);
        const view = child(page, "agendaView");
        tryCompare(view, "count", 3);
        verify(!child(page, "placeholder").enabled);
        Calendar.reset([]);
        verify(child(page, "placeholder").enabled);
    }

    function test_searchPage() {
        const app = makeApp([ev(1, { title: "Dentist" }), ev(2, { title: "Lunch" })]);
        const page = app.pageStack.push(Qt.resolvedUrl("../pages/SearchPage.qml"), { app: app }, PageStackAction.Immediate);
        const view = child(page, "searchView");
        compare(view.count, 0);
        compare(child(page, "placeholder").text, "Search your events");
        page.query = "dent";
        tryCompare(view, "count", 1);
        page.query = "zzz";
        compare(view.count, 0);
        compare(child(page, "placeholder").text, "No matching events");
    }

    function test_eventItemShowsEndAndLocation() {
        const app = makeApp([ev(1, { endTime: "11:30", location: "Room 4", recurring: "weekly" })]);
        const item = child(app.pageStack.currentPage, "eventItem");
        compare(item.details, "Every week · Room 4");
        verify(child(item, "endTimeLabel").visible);
        verify(item.Accessible.name.indexOf("Room 4") !== -1);
        verify(item.Accessible.name.indexOf(app.timeRangeText(Calendar.events[0])) !== -1);
    }

    function test_eventItemOpensAndDeletes() {
        const app = makeApp([ev(1)]);
        const item = child(app.pageStack.currentPage, "eventItem");
        item.clicked(null);
        pushed(app, 2);
        compare(app.pageStack.currentPage.eventId, 1);
        app.pageStack.pop(null, PageStackAction.Immediate);
        pushed(app, 1);
    }
}
