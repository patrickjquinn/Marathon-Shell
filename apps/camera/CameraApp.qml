pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Services 1.0
import MarathonApp.Camera 1.0
import Nemo.Configuration 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property string mode: "photo"
    property bool cameraFailed: false
    // Camera start-up blocks the GUI thread, so it waits until the page is on screen.
    property bool firstFrameShown: false
    readonly property bool latestIsVideo: /\.mp4$/i.test(camera.latestCapture)
    property var gridStore: ConfigurationValue {
        key: "/apps/camera/grid"
        defaultValue: true
    }
    readonly property bool showGrid: gridStore.value === true
    // A camera.capture call waiting for the person's photo or video.
    property var captureCall: null
    property bool captureRecorded: false
    readonly property bool capturing: captureCall !== null
    property Captures captures: Captures {}
    property var camera: CameraController {
        id: cam

        property int timerDuration: 0
        property int timerCountdown: 0
        property bool timerActive: false
        property int recordingDuration: 0
        property string latestCapture: app.captures.latest
        property string latestPreview: app.captures.preview

        function captureWithTimer() {
            if (timerDuration <= 0) {
                capturePhoto(app.captures.nextPath("photo"));
                return;
            }
            timerCountdown = timerDuration;
            timerActive = true;
        }

        function cancelTimer() {
            timerActive = false;
            timerCountdown = 0;
        }

        function deleteLatestCapture() {
            app.captures.deleteLatest();
            latestCapture = Qt.binding(() => app.captures.latest);
            latestPreview = Qt.binding(() => app.captures.preview);
        }

        onErrorOccurred: function (message) {
            console.warn("[Camera] Error:", message);
            if (app.camera.cameraCount === 0)
                return;
            if (app.camera.active)
                Notices.show(app.mode === "video" ? qsTr("Couldn't record video. Check free storage and try again.")
                                                  : qsTr("Couldn't take the photo. Check free storage and try again."));
            else
                app.cameraFailed = true;
        }
        onActiveChanged: {
            if (app.camera.active)
                app.cameraFailed = false;
        }
        onPhotoSaved: function (path) {
            app.captures.add(path);
            if (app.capturing && app.mode === "photo")
                app.returnCapture(path);
        }
        onVideoSaved: function (path) {
            app.captures.add(path);
            if (app.capturing && app.captureRecorded)
                app.returnCapture(path);
        }
        onRecordingChanged: {
            recordingDuration = 0;
            if (app.capturing && isRecording)
                app.captureRecorded = true;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: cam.timerActive
        onTriggered: {
            cam.timerCountdown--;
            if (cam.timerCountdown <= 0) {
                cam.timerActive = false;
                cam.capturePhoto(app.captures.nextPath("photo"));
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: cam.isRecording
        onTriggered: cam.recordingDuration++
    }

    function shoot() {
        if (camera.timerActive)
            camera.cancelTimer();
        else if (mode === "photo")
            camera.captureWithTimer();
        else if (camera.isRecording)
            camera.stopRecording();
        else {
            const path = captures.nextPath("video");
            camera.startRecording(path, captures.posterPath(path));
        }
    }

    function setMode(next) {
        if (!camera.isRecording && !capturing)
            mode = next;
    }

    // camera.capture: the viewfinder in kind's mode; the next capture answers call.
    function beginCapture(call, kind) {
        cancelCapture(qsTr("another capture was asked for"));
        if (!camera.isRecording)
            mode = kind;
        captureCall = call;
        captureRecorded = false;
        if (pageStack.depth > 1)
            pageStack.pop();
        activate();
    }

    function cancelCapture(reason) {
        const call = captureCall;
        captureCall = null;
        if (call && !call.finished)
            call.fail("Cancelled", reason);
    }

    function returnCapture(url) {
        const call = captureCall;
        captureCall = null;
        if (!call || call.finished)
            return;
        call.reply({ path: decodeURIComponent(String(url).replace(/^file:\/\//, "")), mode: mode });
        minimizeRequested();
    }

    function retry() {
        cameraFailed = false;
        camera.cancelTimer();
        camera.stop();
        camera.start();
    }

    function openLatest() {
        if (camera.latestCapture === "")
            Navigation.launchApp("gallery");
        else
            pageStack.push(Qt.resolvedUrl("pages/CaptureReviewPage.qml"), { app: app });
    }

    function handleBack() {
        if (capturing && !camera.isRecording)
            cancelCapture(qsTr("the person left the camera"));
        const page = pageStack.currentPage as CameraPage;
        if (page && page.settingsOpen) {
            page.closeSettings();
            return true;
        }
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        minimizeRequested();
        return true;
    }

    function updateCamera() {
        if (firstFrameShown && applicationActive && pageStack.depth === 1) {
            camera.start();
            return;
        }
        // Finishes the file; stopping the camera alone would cut it off unsaved.
        if (camera.isRecording)
            camera.stopRecording();
        camera.cancelTimer();
        camera.stop();
    }

    appId: "camera"
    onApplicationActiveChanged: {
        if (!applicationActive && capturing && !camera.isRecording)
            cancelCapture(qsTr("the person left the camera"));
        updateCamera();
    }

    Connections {
        target: app.pageStack

        function onDepthChanged() {
            app.updateCamera();
        }
    }

    Connections {
        target: app.Window.window
        enabled: !app.firstFrameShown

        function onFrameSwapped() {
            app.firstFrameShown = true;
            app.updateCamera();
        }
    }

    CameraActions {
        app: app
    }

    cover: Component {
        CameraCover {
            photo: app.camera.latestPreview
        }
    }

    initialPage: Component {
        CameraPage {
            app: app
        }
    }
}
