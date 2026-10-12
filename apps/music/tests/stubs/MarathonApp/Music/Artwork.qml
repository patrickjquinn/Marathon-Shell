pragma Singleton
import QtQml

QtObject {
    property var folders: ({})

    function cache(image, track) {
        return image ? "file:///cache/" + track.split("/").pop() + ".jpg" : "";
    }
    function folderArt(track) {
        return folders[track] || "";
    }
}
