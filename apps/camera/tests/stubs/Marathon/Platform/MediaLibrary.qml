pragma Singleton
import QtQml

QtObject {
    property var photos: []
    property var videos: []
    property var deleted: []

    function reset() {
        photos = [];
        videos = [];
        deleted = [];
    }
    function getAllPhotos() {
        return photos;
    }
    function getVideos() {
        return videos;
    }
    function deleteMedia(id) {
        deleted = deleted.concat([id]);
    }
}
