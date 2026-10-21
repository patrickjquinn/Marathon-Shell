pragma Singleton
import QtQml

QtObject {
    property var folders: ({})

    function art(track) {
        return folders[track] || "";
    }
}
