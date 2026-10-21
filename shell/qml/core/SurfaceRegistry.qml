pragma Singleton
import QtQuick

// The item showing each Wayland surface, for the cards that mirror it.
QtObject {
    id: root

    property var items: ({})

    signal surfaceRegistered(int surfaceId)
    signal surfaceUnregistered(int surfaceId)

    function registerSurface(surfaceId, item) {
        if (surfaceId === -1 || !item)
            return;
        items[surfaceId] = item;
        surfaceRegistered(surfaceId);
    }

    function unregisterSurface(surfaceId) {
        if (!(surfaceId in items))
            return;
        delete items[surfaceId];
        surfaceUnregistered(surfaceId);
    }

    function getSurfaceItem(surfaceId) {
        return items[surfaceId] || null;
    }
}
