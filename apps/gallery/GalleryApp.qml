pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "GalleryModel.js" as Model
import "pages"
import "cover"

ApplicationWindow {
    id: root

    property var albums: MediaLibrary.albums
    property var photos: []
    property var videos: []
    readonly property var memories: Model.memoryClusters(photos, videos, new Date())
    readonly property bool scanning: MediaLibrary.isScanning
    // The photo open full screen, shown on the cover.
    property var viewerPhoto: null

    function refresh() {
        photos = MediaLibrary.getAllPhotos();
        videos = MediaLibrary.getVideos();
    }

    function deletePhoto(id) {
        MediaLibrary.deleteMedia(id);
    }

    appId: "gallery"
    cover: Component {
        GalleryCover {
            photos: root.photos
            photo: root.viewerPhoto
        }
    }
    initialPage: Component {
        GalleryPage {
            store: root
        }
    }
    Component.onCompleted: {
        MediaLibrary.scanLibraryAsync();
        Qt.callLater(refresh);
    }

    GalleryActions {
        store: root
    }

    Connections {
        target: MediaLibrary
        function onScanComplete() { root.refresh(); }
        function onLibraryChanged() { root.refresh(); }
    }
}
