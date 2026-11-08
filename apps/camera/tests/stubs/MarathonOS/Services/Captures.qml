import QtQml

QtObject {
    property string latest
    property string preview
    readonly property var _count: ({
            value: 0
        })

    function nextPath(kind) {
        const n = ++_count.value;
        return kind === "video" ? "/pictures/VID_" + n + ".mp4" : "/pictures/IMG_" + n + ".jpg";
    }
    function posterPath(video) {
        return "/cache/posters/" + video.substring(video.lastIndexOf("/") + 1) + ".jpg";
    }
    function add(capture) {
        latest = capture;
        preview = capture;
    }
    function remove(capture) {
    }
}
