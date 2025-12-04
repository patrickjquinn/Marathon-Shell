pragma Singleton
import QtQuick
import MarathonOS.Shell

Item {
    id: calendarManager

    property var events: []
    property int nextEventId: 1

    // NOTE: Current implementation loads all events into memory.
    // This is suitable for a prototype but may need optimization (e.g. SQLite)
    // for production use with thousands of events.

    signal eventCreated(var event)
    signal eventUpdated(var event)
    signal eventDeleted(int eventId)
    signal eventsLoaded

    // Track triggered events to avoid duplicate notifications
    property var triggeredEvents: []

    function init() {
        _loadEvents();
        _scheduleNextCheck();
    }

    function createEvent(event) {
        // Ensure ID
        if (!event.id) {
            event.id = nextEventId++;
        }

        // Ensure other fields
        event.timestamp = Date.now();

        events.push(event);
        _saveEvents();

        Logger.info("CalendarManager", "Event created: " + event.title + " on " + event.date);
        eventCreated(event);

        return event;
    }

    function updateEvent(event) {
        for (var i = 0; i < events.length; i++) {
            if (events[i].id === event.id) {
                events[i] = event;
                _saveEvents();

                Logger.info("CalendarManager", "Event updated: " + event.title);
                eventUpdated(event);
                return true;
            }
        }
        return false;
    }

    function deleteEvent(id) {
        for (var i = 0; i < events.length; i++) {
            if (events[i].id === id) {
                events.splice(i, 1);
                _saveEvents();

                Logger.info("CalendarManager", "Event deleted: " + id);
                eventDeleted(id);
                return true;
            }
        }
        return false;
    }

    function getEventsForDate(date) {
        var dateStr = Qt.formatDate(date, "yyyy-MM-dd");
        var result = [];

        for (var i = 0; i < events.length; i++) {
            var event = events[i];

            if (event.date === dateStr) {
                result.push(event);
            } else if (event.recurring && event.recurring !== "none") {
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

    function _loadEvents() {
        var savedEvents = SettingsManagerCpp.get("calendar/events", "[]");
        try {
            events = JSON.parse(savedEvents);
            if (events.length > 0) {
                // Ensure IDs are numbers
                events.forEach(e => e.id = Number(e.id));
                nextEventId = Math.max(...events.map(e => e.id)) + 1;
            }
            Logger.info("CalendarManager", "Loaded " + events.length + " events");
            eventsLoaded();
        } catch (e) {
            Logger.error("CalendarManager", "Failed to load events: " + e);
            events = [];
        }
    }

    function _saveEvents() {
        var data = JSON.stringify(events);
        SettingsManagerCpp.set("calendar/events", data);
    }

    function _checkReminders() {
        var now = new Date();
        var currentDateStr = Qt.formatDate(now, "yyyy-MM-dd");
        var currentTimeStr = Qt.formatTime(now, "HH:mm");

        for (var i = 0; i < events.length; i++) {
            var event = events[i];

            // Skip if already triggered recently (simple debounce)
            // In a real app, we'd track this more robustly
            var triggerId = event.id + "_" + currentDateStr + "_" + currentTimeStr;
            if (triggeredEvents.indexOf(triggerId) !== -1) {
                continue;
            }

            var shouldTrigger = false;

            // Check date and time
            if (event.date === currentDateStr && event.time === currentTimeStr) {
                shouldTrigger = true;
            } else if (event.recurring && event.recurring !== "none") {
                // Check recurrence logic
                var eventDate = new Date(event.date);

                if (event.time === currentTimeStr) {
                    if (event.recurring === "daily" && now >= eventDate) {
                        shouldTrigger = true;
                    } else if (event.recurring === "weekly" && now >= eventDate) {
                        var daysDiff = Math.floor((now - eventDate) / (1000 * 60 * 60 * 24));
                        if (daysDiff % 7 === 0) {
                            shouldTrigger = true;
                        }
                    } else if (event.recurring === "monthly" && now >= eventDate) {
                        if (now.getDate() === eventDate.getDate()) {
                            shouldTrigger = true;
                        }
                    }
                }
            }

            if (shouldTrigger) {
                _triggerNotification(event);
                triggeredEvents.push(triggerId);

                // Cleanup old triggered events (keep last 50)
                if (triggeredEvents.length > 50) {
                    triggeredEvents.shift();
                }
            }
        }
    }

    function _triggerNotification(event) {
        Logger.info("CalendarManager", "Triggering notification for: " + event.title);

        NotificationService.sendNotification("calendar", event.title, event.time + (event.allDay ? " (All Day)" : ""), {
            icon: "qrc:/images/calendar.svg",
            category: "reminder",
            priority: "high",
            actions: ["Dismiss"]
        });
    }

    function _scheduleNextCheck() {
        // Align to next minute
        var now = new Date();
        var seconds = now.getSeconds();
        var msToNextMinute = (60 - seconds) * 1000;

        checkTimer.interval = msToNextMinute;
        checkTimer.restart();
    }

    Timer {
        id: checkTimer
        repeat: true
        running: true
        interval: 60000 // Initial interval, adjusted by _scheduleNextCheck
        onTriggered: {
            _checkReminders();

            // Reset to 1 minute interval if we were aligned
            if (interval !== 60000) {
                interval = 60000;
            }
        }
    }

    Component.onCompleted: {
        Logger.info("CalendarManager", "Initialized");
        init();
    }
}
