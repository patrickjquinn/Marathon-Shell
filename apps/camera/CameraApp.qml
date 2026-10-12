pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Camera 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property string mode: "photo"
    property bool cameraFailed: false
    // Camera start-up blocks the GUI thread, so it waits until the page is on screen.
    property bool firstFrameShown: false
    readonly property bool latestIsVideo: /\.mp4$/i.test(camera.latestCapture)
    property CameraController camera: CameraController {
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
    }

    function shoot() {
        if (camera.timerActive)
            camera.cancelTimer();
        else if (mode === "photo")
            camera.captureWithTimer();
        else if (camera.isRecording)
            camera.stopRecording();
        else
            camera.startRecording();
    }

    function setMode(next) {
        if (!camera.isRecording)
            mode = next;
    }

    function retry() {
        cameraFailed = false;
        camera.stop();
        camera.start();
    }

    function openGallery() {
        Navigation.launchApp("gallery");
    }

    function handleBack() {
        const page = pageStack.currentPage;
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
        if (firstFrameShown && applicationActive)
            camera.start();
        else
            camera.stop();
    }

    appId: "camera"
    onApplicationActiveChanged: updateCamera()

    Connections {
        target: app.Window.window
        enabled: !app.firstFrameShown

        function onFrameSwapped() {
            app.firstFrameShown = true;
            app.updateCamera();
        }
    }

    cover: Component {
        CameraCover {
            photo: app.camera.latestPreview
            onCaptureRequested: app.activate()
        }
    }

    initialPage: Component {
        CameraPage {
            app: app
        }
    }
}
