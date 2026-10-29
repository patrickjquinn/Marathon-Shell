pragma Singleton
import QtQml

QtObject {
    signal surfaceRegistered(int surfaceId)
    signal surfaceUnregistered(int surfaceId)
    function getSurfaceItem(surfaceId) {
        return null;
    }
}
