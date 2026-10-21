import QtQml

QtObject {
    property string latest: ""
    property string preview: ""

    function nextPath(kind) {
        return kind === "video" ? "/pictures/VID_1.mp4" : "/pictures/IMG_1.jpg";
    }

    function posterPath(video) {
        return "/cache/posters/VID_1.jpg";
    }

    function add(capture) {
        latest = capture.indexOf("file://") === 0 ? capture : "file://" + capture;
        preview = /\.mp4$/i.test(latest) ? Qt.resolvedUrl("../../../data/photo.png") : latest;
    }

    function deleteLatest() {
        latest = "";
        preview = "";
    }
}
