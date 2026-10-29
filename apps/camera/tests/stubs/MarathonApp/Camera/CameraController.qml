import QtQml

QtObject {
    property QtObject videoSink: null
    property bool discovered: true
    property bool ready: discovered && cameraCount > 0
    property bool active: false
    property int cameraCount: 2
    property int currentCameraIndex: 0
    property string currentCameraName: "Back camera"
    property bool isFrontCamera: false
    property real zoomLevel: 1
    property real minZoom: 1
    property real maxZoom: 4
    property bool flashEnabled: false
    property bool flashAvailable: true
    property var photoResolutions: [Qt.size(4000, 3000), Qt.size(1920, 1080)]
    property size photoResolution: Qt.size(-1, -1)
    property bool isRecording: false
    property var calls: []

    signal errorOccurred(string message)
    signal photoExposed
    signal photoSaved(string path)
    signal videoSaved(string path)
    signal cameraFlipStarted
    signal cameraFlipCompleted
    // The real controller's NOTIFY for isRecording.
    signal recordingChanged

    function record(name) {
        calls = calls.concat([name]);
    }
    function start() {
        record("start");
        if (cameraCount > 0)
            active = true;
    }
    function stop() {
        record("stop");
        active = false;
    }
    function flipCamera() {
        record("flipCamera");
        cameraFlipStarted();
    }
    function capturePhoto(path) {
        record("capturePhoto");
        record("captureWithTimer");
    }
    function startRecording(path, posterPath) {
        record("startRecording");
        isRecording = true;
        recordingChanged();
    }
    function stopRecording() {
        record("stopRecording");
        isRecording = false;
        recordingChanged();
        videoSaved("file:///pictures/VID_1.mp4");
    }
    function focusOnPoint(x, y) {
        record("focusOnPoint");
    }
}
