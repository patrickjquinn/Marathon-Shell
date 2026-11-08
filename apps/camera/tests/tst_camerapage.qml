import QtQuick
import QtTest
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

TestCase {
    id: testCase

    name: "CameraPage"
    when: windowShown
    visible: true
    width: 720
    height: 1064

    Component {
        id: appComponent
        CameraApp {}
    }

    // Each window is the panel less the status and gesture bars.
    function windows() {
        return [
            {
                tag: "Zinwa Q25, 720x720 at 240 dpi",
                width: 720,
                height: 633
            },
            {
                tag: "phone canvas, 540x1140 at 160 dpi",
                width: 540,
                height: 1064
            }
        ];
    }

    function init() {
        Settings.global.captureMode = "image";
        Settings.global.portraitCaptureButtonLocation = 3;
        Settings.global.landscapeCaptureButtonLocation = 5;
    }

    function makeApp(data) {
        const app = createTemporaryObject(appComponent, testCase, {
            width: data.width,
            height: data.height
        });
        tryVerify(() => app.cameraPage && app.cameraPage.captureView.captureOverlay, 5000);
        const overlay = app.cameraPage.captureView.captureOverlay;
        tryVerify(() => app.camera.controller.active && overlay.opacity === 1, 5000);
        tryVerify(() => findChild(app, "shutter").enabled);
        return app;
    }

    function rect(app, item) {
        const p = item.mapToItem(app, 0, 0);
        return Qt.rect(p.x, p.y, item.width, item.height);
    }

    function verifyInside(app, name) {
        const item = findChild(app, name);
        verify(item, name);
        verify(item.visible, name + " is shown");
        const r = rect(app, item);
        verify(r.x >= 0 && r.x + r.width <= app.width, name + " spans x " + r.x + "-" + (r.x + r.width) + " of " + app.width);
        verify(r.y >= 0 && r.y + r.height <= app.height, name + " spans y " + r.y + "-" + (r.y + r.height) + " of " + app.height);
        return r;
    }

    function overlaps(a, b) {
        return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
    }

    function test_controlsFitTheWindow_data() {
        return windows();
    }

    function test_controlsFitTheWindow(data) {
        const app = makeApp(data);
        const shutter = verifyInside(app, "shutter");
        const controls = ["imageMode", "videoMode", "cameraSwitch"].map(name => verifyInside(app, name));
        for (const control of controls)
            verify(!overlaps(shutter, control), "a control overlaps the shutter");
        verify(!overlaps(controls[0], controls[1]), "the photo and video switches overlap");
        verify(shutter.y > app.height / 2, "the shutter is in the lower half, at " + shutter.y);
        verify(Math.abs(shutter.x + shutter.width / 2 - app.width / 2) <= 1, "the shutter is centred, at " + shutter.x);
    }

    function test_shutterTakesAPhoto_data() {
        return windows();
    }

    // A tap where the shutter is drawn reaches it, not a control above it.
    function test_shutterTakesAPhoto(data) {
        const app = makeApp(data);
        const r = rect(app, findChild(app, "shutter"));
        mouseClick(app, r.x + r.width / 2, r.y + r.height / 2);
        compare(app.camera.controller.photos.length, 1);
    }

    function test_videoSwitchRecords_data() {
        return windows();
    }

    function test_videoSwitchRecords(data) {
        const app = makeApp(data);
        const video = rect(app, findChild(app, "videoMode"));
        mouseClick(app, video.x + video.width / 2, video.y + video.height / 2);
        compare(Settings.global.captureMode, "video");
        tryVerify(() => findChild(app, "shutter").enabled);
        verifyInside(app, "shutter");
        const r = rect(app, findChild(app, "shutter"));
        mouseClick(app, r.x + r.width / 2, r.y + r.height / 2);
        tryVerify(() => app.recording);
        mouseClick(app, r.x + r.width / 2, r.y + r.height / 2);
        tryVerify(() => !app.recording);
    }
}
