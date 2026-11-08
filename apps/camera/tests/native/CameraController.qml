import QtQuick

// The C++ CameraController's QML surface, with a back and a front camera.
QtObject {
    property QtObject videoSink: null
    property bool discovered: false
    property bool active: false
    readonly property int cameraCount: discovered ? cameras.length : 0
    readonly property var cameras: discovered ? [
        {
            id: "back",
            description: "Back camera",
            position: 1,
            rotation: 90
        },
        {
            id: "front",
            description: "Front camera",
            position: 2,
            rotation: 270
        }
    ] : []
    readonly property string defaultCameraId: discovered ? "back" : ""
    property string cameraId
    readonly property var previewResolutions: [Qt.size(1920, 1080), Qt.size(1280, 960), Qt.size(640, 480)]
    property size viewfinderResolution: Qt.size(-1, -1)
    property real zoomLevel: 1
    readonly property real maxZoom: 4
    property bool flashEnabled: false
    readonly property bool flashAvailable: false
    readonly property var photoResolutions: [Qt.size(4000, 3000), Qt.size(1920, 1080)]
    property size photoResolution: Qt.size(-1, -1)
    property bool isRecording: false
    property var photos: []

    signal errorOccurred(string message)
    signal photoExposed
    signal photoSaved(string url)
    signal videoSaved(string url)

    function discover() {
        discovered = true;
    }
    function start() {
        active = discovered;
    }
    function stop() {
        active = false;
    }
    function capturePhoto(path, rotation) {
        photos = photos.concat([path]);
        photoExposed();
        photoSaved("file://" + path);
    }
    function startRecording(path, posterPath) {
        isRecording = true;
    }
    function stopRecording() {
        isRecording = false;
    }
    function focusOnPoint(x, y) {
    }
}
