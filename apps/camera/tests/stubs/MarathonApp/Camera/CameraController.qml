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
    property int timerDuration: 0
    property int timerCountdown: 0
    property bool timerActive: false
    property bool isRecording: false
    property int recordingDuration: 0
    property string latestCapture: ""
    property string latestPreview: ""
    property var calls: []

    signal errorOccurred(string message)
    signal photoSaved(string path)
    signal cameraFlipStarted
    signal cameraFlipCompleted

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
    function capturePhoto() { record("capturePhoto"); }
    function captureWithTimer() {
        record("captureWithTimer");
        if (timerDuration > 0) {
            timerCountdown = timerDuration;
            timerActive = true;
        }
    }
    function cancelTimer() {
        record("cancelTimer");
        timerActive = false;
        timerCountdown = 0;
    }
    function startRecording() {
        record("startRecording");
        isRecording = true;
    }
    function stopRecording() {
        record("stopRecording");
        isRecording = false;
        latestCapture = "file:///pictures/VID_1.mp4";
        latestPreview = Qt.resolvedUrl("../../../data/photo.png");
    }
    function focusOnPoint(x, y) { record("focusOnPoint"); }
}
