import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "GalleryModel.js" as Model
import "pages"

ApplicationWindow {
    id: root

    property var albums: MediaLibrary.albums
    property var photos: []
    property var videos: []
    readonly property var memories: Model.memoryClusters(photos, videos, new Date())
    readonly property bool scanning: MediaLibrary.isScanning

    function refresh() {
        photos = MediaLibrary.getAllPhotos();
        videos = MediaLibrary.getVideos();
    }

    function deletePhoto(id) {
        MediaLibrary.deleteMedia(id);
    }

    appId: "gallery"
    initialPage: Component {
        GalleryPage {
            store: root
        }
    }
    Component.onCompleted: {
        MediaLibrary.scanLibraryAsync();
        Qt.callLater(refresh);
    }

    Connections {
        target: MediaLibrary
        function onScanComplete() { root.refresh(); }
        function onLibraryChanged() { root.refresh(); }
    }
}
