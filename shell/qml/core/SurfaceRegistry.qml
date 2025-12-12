pragma Singleton
import QtQuick
import MarathonUI.Core

QtObject {
    id: surfaceRegistry

    property var surfaceMap: ({})

    function registerSurface(surfaceId, item) {
        if (surfaceId !== -1 && item) {
            surfaceMap[surfaceId] = item;
            Logger.info("SurfaceRegistry", "Registered surface: " + surfaceId);
        }
    }

    function unregisterSurface(surfaceId) {
        if (surfaceMap[surfaceId]) {
            delete surfaceMap[surfaceId];
            Logger.info("SurfaceRegistry", "Unregistered surface: " + surfaceId);
        }
    }

    function getSurfaceItem(surfaceId) {
        return surfaceMap[surfaceId] || null;
    }
}
