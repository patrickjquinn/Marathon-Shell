import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "CameraApp"
    when: windowShown
    visible: true
    width: 720
    height: 1440

    Component {
        id: appComponent
        CameraApp { width: 720; height: 1440 }
    }

    function makeApp() {
        Navigation.reset();
        Permissions.reset();
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(function () { return app.pageStack.currentPage !== null && !app.pageStack.busy; });
        app.camera.start();
        return app;
    }

    function child(app, name) {
        const item = findChild(app.pageStack.currentPage, name);
        verify(item, name);
        return item;
    }

    function openSettings(app) {
        mouseClick(child(app, "settingsButton"));
        const panel = child(app, "settingsPanel");
        tryCompare(panel, "moving", false);
        verify(panel.open);
        return panel;
    }

    function test_hooksTheViewfinderUp() {
        const app = makeApp();
        compare(app.camera.videoSink, child(app, "viewfinder").videoSink);
        verify(child(app, "shutter").visible);
    }

    function test_shutterTakesAPhoto() {
        const app = makeApp();
        mouseClick(child(app, "shutter"));
        compare(app.camera.calls[app.camera.calls.length - 1], "captureWithTimer");
    }

    function test_keysTakeAPhoto() {
        const app = makeApp();
        app.pageStack.currentPage.forceActiveFocus();
        const before = app.camera.calls.filter(c => c === "captureWithTimer").length;
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Return);
        compare(app.camera.calls.filter(c => c === "captureWithTimer").length, before + 2);
    }

    function test_videoModeRecords() {
        const app = makeApp();
        mouseClick(child(app, "videoMode"));
        compare(app.mode, "video");
        mouseClick(child(app, "shutter"));
        verify(app.camera.isRecording);
        verify(child(app, "recordingIndicator").visible);
        app.camera.recordingDuration = 65;
        compare(child(app, "recordingTime").text, "1:05");
        app.setMode("photo");
        compare(app.mode, "video");
        mouseClick(child(app, "shutter"));
        verify(!app.camera.isRecording);
        mouseClick(child(app, "photoMode"));
        compare(app.mode, "photo");
    }

    function test_modeSwitchHighlightsTheCurrentMode() {
        const app = makeApp();
        const photo = child(app, "photoMode");
        const video = child(app, "videoMode");
        verify(photo.icon.highlighted);
        verify(!video.icon.highlighted);
        compare(child(app, "photoModeLabel").color, Theme.highlightColor);
        verify(child(app, "modeSwitch").color === undefined);
        mouseClick(video);
        tryVerify(function () { return !photo.icon.highlighted; });
        verify(video.icon.highlighted);
        compare(child(app, "videoModeLabel").color, Theme.highlightColor);
    }

    function test_thumbnailOpensGallery() {
        const app = makeApp();
        app.camera.latestPhotoPath = Qt.resolvedUrl("data/photo.png");
        verify(child(app, "thumbnailImage").visible);
        mouseClick(child(app, "thumbnail"));
        compare(Navigation.launches, ["gallery"]);
    }

    function test_settingsCloseOnBackAndEscape() {
        const app = makeApp();
        openSettings(app);
        verify(app.pageStack.currentPage.settingsOpen);
        app.handleBack();
        verify(!app.pageStack.currentPage.settingsOpen);
        tryCompare(child(app, "settingsPanel"), "moving", false);
        openSettings(app);
        app.pageStack.currentPage.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        verify(!app.pageStack.currentPage.settingsOpen);
    }

    function test_swipeDownOpensSettings() {
        const app = makeApp();
        const area = child(app, "gestureArea");
        mouseDrag(area, area.width / 2, area.height / 3, 0, area.height / 4);
        tryVerify(function () { return app.pageStack.currentPage.settingsOpen; });
    }

    function test_flashSwitch() {
        const app = makeApp();
        openSettings(app);
        const flash = child(app, "flashSwitch");
        mouseClick(flash);
        verify(app.camera.flashEnabled);
        mouseClick(flash);
        verify(!app.camera.flashEnabled);
        app.camera.flashAvailable = false;
        verify(!flash.enabled);
    }

    function test_timerAndResolution() {
        const app = makeApp();
        const panel = openSettings(app);
        const timer = child(app, "timerCombo");
        compare(timer.value, "Off");
        app.camera.timerDuration = 10;
        compare(timer.value, "10 seconds");
        const resolution = child(app, "resolutionCombo");
        compare(resolution.value, "Automatic");
        app.camera.photoResolution = Qt.size(1920, 1080);
        compare(resolution.currentIndex, 2);
        compare(panel.resolutionText(Qt.size(4000, 3000)), "4000 × 3000 (12.0 MP)");
        app.camera.photoResolutions = [];
        verify(!resolution.visible);
    }

    function test_flipCamera() {
        const app = makeApp();
        const flip = findChild(app.pageStack.currentPage, "flipButton");
        mouseClick(flip);
        compare(app.camera.calls[app.camera.calls.length - 1], "flipCamera");
        app.camera.cameraCount = 1;
        verify(!flip.enabled);
    }

    function test_failureShowsPlaceholderAndRetries() {
        const app = makeApp();
        app.camera.stop();
        app.camera.errorOccurred("busy");
        verify(app.cameraFailed);
        verify(child(app, "problem").visible);
        verify(!child(app, "shutter").visible);
        compare(child(app, "problemAction").text, "Try again");
        app.retry();
        verify(!app.cameraFailed);
        verify(app.camera.active);
        verify(!child(app, "problem").visible);
    }

    function test_errorWhileActiveIsANotice() {
        const app = makeApp();
        app.camera.errorOccurred("disk full");
        verify(!app.cameraFailed);
    }

    function test_noCameraAsksForPermission() {
        const app = makeApp();
        app.camera.cameraCount = 0;
        verify(child(app, "problem").visible);
        const action = child(app, "problemAction");
        compare(action.text, "Grant camera access");
        action.clicked();
        compare(Permissions.requests, ["camera:camera"]);
    }

    function test_shutterCancelsTheTimer() {
        const app = makeApp();
        app.camera.timerDuration = 3;
        const shutter = child(app, "shutter");
        mouseClick(shutter);
        verify(app.camera.timerActive);
        compare(shutter.Accessible.name, "Cancel timer");
        verify(shutter.stopGlyph);
        mouseClick(shutter);
        compare(app.camera.calls[app.camera.calls.length - 1], "cancelTimer");
        verify(!app.camera.timerActive);
        verify(!child(app, "countdown").visible);
        compare(shutter.Accessible.name, "Take photo");
    }

    function test_countdownShowsWhileTimerRuns() {
        const app = makeApp();
        const countdown = child(app, "countdown");
        verify(!countdown.visible);
        app.camera.timerActive = true;
        app.camera.timerCountdown = 3;
        verify(countdown.visible);
        compare(countdown.text, "3");
    }
}
