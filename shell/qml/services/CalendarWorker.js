
WorkerScript.onMessage = function (message) {
    if (message.action === 'processEvents') {
        try {
            var events = message.events;

            for (var i = 0; i < events.length; i++) {
                events[i].id = Number(events[i].id);
            }

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
