pragma Singleton
import QtQml

QtObject {
    property var albums: []
    property bool isScanning: false
    property var photos: []
    property var videos: []
    property var deleted: []
    property int scans: 0

    signal scanComplete(int photoCount, int videoCount)
    signal libraryChanged

    function scanLibraryAsync() { scans++; }
    function getAllPhotos() { return photos; }
    function getVideos() { return videos; }
    function deleteMedia(id) {
        deleted = deleted.concat([id]);
        photos = photos.filter(p => p.id !== id);
        libraryChanged();
    }
}
