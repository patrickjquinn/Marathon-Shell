pragma Singleton
import QtQuick
import MarathonOS.Shell
import QtQuick.LocalStorage 2.0

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

    property var db: null

    function initDatabase() {
        db = LocalStorage.openDatabaseSync("CalendarDB", "1.0", "Calendar Events", 100000);
        db.transaction(function (tx) {
            tx.executeSql(`CREATE TABLE IF NOT EXISTS events(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT,
                date TEXT,
                time TEXT,
                allDay INTEGER,
                recurring TEXT,
                description TEXT
            )`);
        });
    }

    function init() {
        initDatabase();
        _loadEvents();
        _scheduleNextCheck();
    }

    function createEvent(event) {
        var resId = -1;
        db.transaction(function (tx) {
            var rs = tx.executeSql(`INSERT INTO events (title, date, time, allDay, recurring, description) VALUES (?, ?, ?, ?, ?, ?)`, [event.title, event.date, event.time, event.allDay ? 1 : 0, event.recurring || "none", event.description || ""]);
            resId = rs.insertId;
        });

        if (resId !== -1) {
            event.id = resId;
            // Add to local model for immediate feedback
            events.push(event);
            Logger.info("CalendarManager", "Event created: " + event.title + " (ID: " + resId + ")");
            eventCreated(event);
            return event;
        }
        return null;
    }

    function updateEvent(event) {
        var success = false;
        db.transaction(function (tx) {
            var rs = tx.executeSql(`UPDATE events SET title=?, date=?, time=?, allDay=?, recurring=?, description=? WHERE id=?`, [event.title, event.date, event.time, event.allDay ? 1 : 0, event.recurring || "none", event.description || "", event.id]);
            if (rs.rowsAffected > 0) {
                success = true;
            }
        });

        if (success) {
            // Update local model
            for (var i = 0; i < events.length; i++) {
                if (events[i].id === event.id) {
                    events[i] = event;
                    break;
                }
            }
            Logger.info("CalendarManager", "Event updated: " + event.title);
            eventUpdated(event);
            return true;
        }
        return false;
    }

    function deleteEvent(id) {
        var success = false;
        db.transaction(function (tx) {
            var rs = tx.executeSql(`DELETE FROM events WHERE id=?`, [id]);
            if (rs.rowsAffected > 0) {
                success = true;
            }
        });

        if (success) {
            // Update local model
            for (var i = 0; i < events.length; i++) {
                if (events[i].id === id) {
                    events.splice(i, 1);
                    break;
                }
            }
            Logger.info("CalendarManager", "Event deleted: " + id);
            eventDeleted(id);
            return true;
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

    WorkerScript {
        id: calendarWorker
        source: "CalendarWorker.js"
        onMessage: function (message) {
            if (message.action === 'eventsParsed') {
                calendarManager.events = message.events;
                Logger.info("CalendarManager", "Loaded " + calendarManager.events.length + " events from DB");
                eventsLoaded();
            } else if (message.action === 'error') {
                Logger.error("CalendarManager", "Worker failed: " + message.error);
                calendarManager.events = [];
            }
        }
    }

    function _loadEvents() {
        var rawEvents = [];
        db.transaction(function (tx) {
            var rs = tx.executeSql(`SELECT * FROM events`);
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                // Convert SQLite types to JS types where needed
                rawEvents.push({
                    id: row.id,
                    title: row.title,
                    date: row.date,
                    time: row.time,
                    allDay: row.allDay === 1,
                    recurring: row.recurring,
                    description: row.description
                });
            }
        });

        // Send to worker for any heavy processing (sorting, expansion)
        // Even if we don't need parsing, the worker can handle sorting/filtering
        calendarWorker.sendMessage({
            'action': 'processEvents',
            'events': rawEvents
        });
    }

    function _saveEvents() {
    // No-op: SQLite saves immediately
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
