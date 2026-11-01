pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0 as Platform
import MarathonApp.Camera 1.0

ApplicationWindow {
    id: app

    // Read by the cover, as the window's own.
    property var captureModel: null
    property bool galleryActive
    property bool galleryVisible
    property int galleryIndex

    property CameraPage cameraPage
    readonly property Camera camera: cameraPage ? cameraPage.captureView.camera : null
    // Cameras are only enumerated once the camera first starts.
    readonly property bool noCamera: !!camera && camera.controller.discovered && camera.controller.cameraCount === 0
    readonly property string mode: Settings.global.captureMode === "video" ? "video" : "photo"
    readonly property bool recording: !!camera && camera.videoRecorder.recording
    // Camera start-up blocks the GUI thread, so it waits until the page is on screen.
    property bool firstFrameShown: false
    // A camera.capture call waiting for the person's photo or video.
    property var captureCall: null
    property bool captureRecorded: false
    readonly property bool capturing: captureCall !== null
    // Keeps a recording going while the app is in the background.
    property int _recordingTask: 0

    function setMode(next) {
        if (!recording && !capturing)
            Settings.global.captureMode = next === "video" ? "video" : "image";
    }

    // camera.capture: the viewfinder in kind's mode; the next capture answers call.
    function beginCapture(call, kind) {
        cancelCapture(qsTr("another capture was asked for"));
        if (!recording)
            Settings.global.captureMode = kind === "video" ? "video" : "image";
        captureCall = call;
        captureRecorded = false;
        if (pageStack.depth > 1)
            pageStack.pop(cameraPage, PageStackAction.Immediate);
        cameraPage.returnToCaptureMode();
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
        call.reply({
            path: decodeURIComponent(String(url).replace(/^file:\/\//, "")),
            mode: mode
        });
        minimizeRequested();
    }

    function handleBack() {
        if (capturing && !recording)
            cancelCapture(qsTr("the person left the camera"));
        const overlay = cameraPage ? cameraPage.captureView.captureOverlay : null;
        if (overlay && (overlay.topMenuOpen || overlay.inButtonLayout)) {
            overlay.closeMenus();
            return true;
        }
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        if (cameraPage && !cameraPage.captureModeActive) {
            cameraPage.returnToCaptureMode();
            return true;
        }
        minimizeRequested();
        return true;
    }

    appId: "camera"
    allowedOrientations: defaultAllowedOrientations
    _defaultPageOrientations: Orientation.All

    onApplicationActiveChanged: {
        if (!applicationActive && capturing && !recording)
            cancelCapture(qsTr("the person left the camera"));
    }
    onRecordingChanged: {
        if (recording && capturing)
            captureRecorded = true;
        if (recording && _recordingTask === 0) {
            _recordingTask = Platform.Lifecycle.beginBackgroundTask("recording", "recording video");
        } else if (!recording && _recordingTask !== 0) {
            Platform.Lifecycle.endBackgroundTask(_recordingTask);
            _recordingTask = 0;
        }
    }

    Connections {
        target: app.Window.window
        enabled: !app.firstFrameShown

        function onFrameSwapped() {
            app.firstFrameShown = true;
        }
    }

    Connections {
        target: app.cameraPage ? app.cameraPage.captureView : null

        function onRecordingStopped(url, mimeType) {
            if (app.capturing && app.captureRecorded)
                app.returnCapture(url);
        }
    }

    Connections {
        target: app.camera ? app.camera.imageCapture : null

        function onImageSaved(requestId, path) {
            if (app.capturing && app.mode === "photo")
                app.returnCapture(path);
        }
        function onCaptureFailed(requestId, message) {
            Notices.show(qsTr("Couldn't take the photo. Check free storage and try again."));
        }
    }

    Connections {
        target: app.camera

        function onError(message) {
            console.warn("[Camera] Error:", message);
            if (app.recording)
                Notices.show(qsTr("Couldn't record video. Check free storage and try again."));
        }
    }

    CameraActions {
        app: app
    }

    // A component of this document, so that the cover sees the window's
    // properties (galleryActive, captureModel, ...).
    cover: Component {
        CameraCover {}
    }

    initialPage: Component {
        CameraPage {
            id: page

            viewfinder: videoOutput
            galleryView: Qt.resolvedUrl("gallery/MainGalleryView.qml")
            captureView.cameraAllowed: app.firstFrameShown

            Component.onCompleted: app.cameraPage = page

            // Back to the viewfinder, and zoom reset, after a while away.
            Timer {
                running: !app.applicationActive && !page.captureModeActive
                interval: 15 * 60 * 1000
                onTriggered: page.returnToCaptureMode()
            }
            Timer {
                running: !app.applicationActive || !page.captureModeActive
                interval: 5 * 60 * 1000
                onTriggered: page.resetZoom()
            }

            Binding {
                target: app
                property: "galleryActive"
                value: page.galleryActive
            }
            Binding {
                target: app
                property: "galleryVisible"
                value: page.galleryVisible
            }
            Binding {
                target: app
                property: "galleryIndex"
                value: page.galleryIndex
            }
            Binding {
                target: app
                property: "captureModel"
                value: page.captureModel
            }
        }
    }

    // Behind the pages: black, and the viewfinder, which does not turn with them.
    Rectangle {
        parent: app
        anchors.fill: parent
        z: -1
        color: "black"
        visible: (app.pageStack.depth < 2 && !app.pageStack.busy) || !app.galleryActive
    }

    VideoOutput {
        id: videoOutput

        z: -1
        width: app.width
        height: app.height

        Behavior on y {
            enabled: !app.galleryVisible
            NumberAnimation {
                duration: 150
                easing.type: Easing.InOutQuad
            }
        }
    }
}
