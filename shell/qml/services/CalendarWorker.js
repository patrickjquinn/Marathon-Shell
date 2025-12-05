WorkerScript.onMessage = function (message) {
    if (message.action === 'processEvents') {
        try {
            // Events are already objects from the main thread's SQL result
            var events = message.events;

            // Perform any necessary processing (sorting, filtering, expansion)
            // For now, we just ensure IDs are numbers (though they should be from SQL)
            for (var i = 0; i < events.length; i++) {
                events[i].id = Number(events[i].id);
            }

            // Sort by date/time
            events.sort(function (a, b) {
                var dateA = new Date(a.date + "T" + a.time);
                var dateB = new Date(b.date + "T" + b.time);
                return dateA - dateB;
            });

            WorkerScript.sendMessage({
                'action': 'eventsParsed',
                'events': events
            });
        } catch (e) {
            console.error("CalendarWorker: Failed to process events: " + e);
            WorkerScript.sendMessage({
                'action': 'error',
                'error': e.toString()
            });
        }
    }
}
