pragma Singleton
import MarathonOS.Shell
import QtQuick

QtObject {
    id: root

    property var events: []
    property int nextEventId: 1
    property Connections calendarConnection

    signal dataChanged

    function init() {
        if (typeof CalendarManager === "undefined")
            return;

        events = CalendarManager.events;
        nextEventId = CalendarManager.nextEventId;
        dataChanged();
    }

    function save() {
        dataChanged();
    }

    function addEvent(event) {
        if (typeof CalendarManager === "undefined")
            return null;

        var newEvent = CalendarManager.createEvent(event);
        events = CalendarManager.events;
        dataChanged();
        return newEvent;
    }

    function updateEvent(event) {
        if (typeof CalendarManager === "undefined")
            return false;

        var result = CalendarManager.updateEvent(event);
        events = CalendarManager.events;
        dataChanged();
        return result;
    }

    function deleteEvent(id) {
        if (typeof CalendarManager === "undefined")
            return false;

        var result = CalendarManager.deleteEvent(id);
        events = CalendarManager.events;
        dataChanged();
        return result;
    }

    function getEventsForDate(date) {
        if (typeof CalendarManager === "undefined")
            return [];

        return CalendarManager.getEventsForDate(date);
    }

    function getAllEvents() {
        return events;
    }

    calendarConnection: Connections {
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

        target: typeof CalendarManager !== "undefined" ? CalendarManager : null
        enabled: typeof CalendarManager !== "undefined"
    }
}
