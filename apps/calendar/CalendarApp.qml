import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "CalendarLogic.js" as Logic
import "pages"
import "cover"

ApplicationWindow {
    id: root

    readonly property var events: Calendar.events || []

    function eventsOn(date) {
        return Logic.eventsOn(events, date);
    }

    function eventById(id) {
        return events.find(e => e.id === id) || null;
    }

    function repeatText(mode) {
        switch (mode) {
        case "daily":
            return qsTr("Every day");
        case "weekly":
            return qsTr("Every week");
        case "monthly":
            return qsTr("Every month");
        default:
            return qsTr("Never");
        }
    }

    function reminderText(minutes) {
        if (minutes < 0)
            return qsTr("None");
        if (minutes === 0)
            return qsTr("At time of event");
        if (minutes === 1440)
            return qsTr("1 day before");
        if (minutes === 60)
            return qsTr("1 hour before");
        return qsTr("%1 minutes before").arg(minutes);
    }

    function timeText(event) {
        if (event.allDay)
            return qsTr("All day");
        const t = Logic.parseTime(event.time);
        return Format.formatDate(new Date(2000, 0, 1, t.hour, t.minute), Formatter.TimeValue);
    }

    function timeRangeText(event) {
        if (event.allDay || !event.endTime)
            return timeText(event);
        const t = Logic.parseTime(event.endTime);
        const end = Format.formatDate(new Date(2000, 0, 1, t.hour, t.minute), Formatter.TimeValue);
        return Logic.endsNextDay(event) ? qsTr("%1 – %2 next day").arg(timeText(event)).arg(end) : qsTr("%1 – %2").arg(timeText(event)).arg(end);
    }

    function dateText(event) {
        return Format.formatDate(Logic.parseDate(event.date), Formatter.DateLong);
    }

    // `event` without an id is created.
    function saveEvent(event) {
        const ok = event.id === undefined ? Calendar.createEvent(event).id !== undefined : Calendar.updateEvent(event);
        if (!ok)
            Notices.show(qsTr("Couldn't save the event. Try again."));
        return ok;
    }

    function deleteEvent(id) {
        const ok = Calendar.deleteEvent(id);
        if (!ok)
            Notices.show(qsTr("Couldn't delete the event. Try again."));
        return ok;
    }

    function openEvent(event) {
        return pageStack.push(Qt.resolvedUrl("pages/EventPage.qml"), { app: root, eventId: event.id });
    }

    function newEvent(date) {
        const start = new Date();
        start.setHours(start.getHours() + 1, 0, 0, 0);
        const onToday = !date || Logic.dateKey(date) === Logic.dateKey(new Date());
        return pageStack.push(Qt.resolvedUrl("pages/EventEditorDialog.qml"), {
            app: root,
            date: onToday ? start : date,
            hour: start.getHours(),
            minute: 0
        });
    }

    function editEvent(event) {
        const t = Logic.parseTime(event.time);
        return pageStack.push(Qt.resolvedUrl("pages/EventEditorDialog.qml"), {
            app: root,
            original: event,
            title: event.title || "",
            date: Logic.parseDate(event.date),
            hour: t.hour,
            minute: t.minute,
            duration: event.endTime ? Logic.duration(event.time, event.endTime) : 60,
            location: event.location || "",
            allDay: !!event.allDay,
            recurring: event.recurring || "none",
            reminder: event.reminder === undefined ? 0 : event.reminder,
            description: event.description || ""
        });
    }

    appId: "calendar"
    cover: Component {
        CalendarCover {
            events: root.events
            onNewEventRequested: {
                root.activate();
                root.newEvent(new Date());
            }
        }
    }
    initialPage: Component {
        MonthPage {
            app: root
        }
    }
}
