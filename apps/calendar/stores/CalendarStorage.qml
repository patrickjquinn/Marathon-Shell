pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root

    property var events: []
    property int nextEventId: 1

    // Signal to notify listeners of changes
    signal dataChanged

    function init() {
        if (typeof CalendarManager !== 'undefined') {
            events = CalendarManager.events;
            nextEventId = CalendarManager.nextEventId;
        } else {
            var savedEvents = SettingsManagerCpp.get("calendar/events", "[]");
            try {
                events = JSON.parse(savedEvents);
                if (events.length > 0) {
                    // Ensure IDs are numbers
                    events.forEach(e => e.id = Number(e.id));
                    nextEventId = Math.max(...events.map(e => e.id)) + 1;
                }
            } catch (e) {
                Logger.error("CalendarStorage", "Failed to load events: " + e);
                events = [];
            }
        }
        dataChanged();
    }

    function save() {
        // No-op if using CalendarManager, it handles saving
        if (typeof CalendarManager === 'undefined') {
            var data = JSON.stringify(events);
            SettingsManagerCpp.set("calendar/events", data);
            dataChanged();
        }
    }

    function addEvent(event) {
        if (typeof CalendarManager !== 'undefined') {
            var newEvent = CalendarManager.createEvent(event);
            events = CalendarManager.events;
            dataChanged();
            return newEvent;
        } else {
            event.id = nextEventId++;
            event.timestamp = Date.now();
            events.push(event);
            save();
            return event;
        }
    }

    function updateEvent(event) {
        if (typeof CalendarManager !== 'undefined') {
            var result = CalendarManager.updateEvent(event);
            events = CalendarManager.events;
            dataChanged();
            return result;
        } else {
            for (var i = 0; i < events.length; i++) {
                if (events[i].id === event.id) {
                    events[i] = event;
                    save();
                    return true;
                }
            }
            return false;
        }
    }

    function deleteEvent(id) {
        if (typeof CalendarManager !== 'undefined') {
            var result = CalendarManager.deleteEvent(id);
            events = CalendarManager.events;
            dataChanged();
            return result;
        } else {
            for (var i = 0; i < events.length; i++) {
                if (events[i].id === id) {
                    events.splice(i, 1);
                    save();
                    return true;
                }
            }
            return false;
        }
    }

    function getEventsForDate(date) {
        if (typeof CalendarManager !== 'undefined') {
            return CalendarManager.getEventsForDate(date);
        }

        var dateStr = Qt.formatDate(date, "yyyy-MM-dd");
        var result = [];

        for (var i = 0; i < events.length; i++) {
            var event = events[i];

            if (event.date === dateStr) {
                result.push(event);
            } else if (event.recurring !== "none") {
                var eventDate = new Date(event.date);
                var checkDate = new Date(date);

                if (event.recurring === "daily" && checkDate >= eventDate) {
                    result.push(event);
                } else if (event.recurring === "weekly" && checkDate >= eventDate) {
                    var daysDiff = Math.floor((checkDate - eventDate) / (1000 * 60 * 60 * 24));
                    if (daysDiff % 7 === 0) {
                        result.push(event);
                    }
                } else if (event.recurring === "monthly" && checkDate >= eventDate) {
                    if (checkDate.getDate() === eventDate.getDate()) {
                        result.push(event);
                    }
                }
            }
        }
        return result;
    }

    function getAllEvents() {
        return events;
    }

    property Connections calendarConnection: Connections {
        target: typeof CalendarManager !== 'undefined' ? CalendarManager : null
        enabled: typeof CalendarManager !== 'undefined'

        function onEventsLoaded() {
            root.events = CalendarManager.events;
            root.dataChanged();
        }

        function onEventCreated(event) {
            root.events = CalendarManager.events;
            root.dataChanged();
        }

        function onEventUpdated(event) {
            root.events = CalendarManager.events;
            root.dataChanged();
        }

        function onEventDeleted(eventId) {
            root.events = CalendarManager.events;
            root.dataChanged();
        }
    }
}
