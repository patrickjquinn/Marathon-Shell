pragma Singleton
import QtQml

QtObject {
    property var events: []
    property bool fail: false
    property int nextId: 1

    function reset(list) {
        events = list || [];
        fail = false;
        nextId = 100;
    }

    function createEvent(event) {
        if (fail)
            return {};
        const created = Object.assign({}, event, { id: nextId++ });
        events = events.concat([created]);
        return created;
    }

    function updateEvent(event) {
        if (fail || !events.some(e => e.id === event.id))
            return false;
        events = events.map(e => e.id === event.id ? Object.assign({}, event) : e);
        return true;
    }

    function deleteEvent(id) {
        if (fail || !events.some(e => e.id === id))
            return false;
        events = events.filter(e => e.id !== id);
        return true;
    }
}
