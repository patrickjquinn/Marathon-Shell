import QtQuick
import Keel.Actions 1.0

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml CameraActions.qml \
//       --app-id org.marathonos.camera --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: camera, mode, setMode(), beginCapture(), pageStack and activate().
    property var app

    KeelAction {
        name: "camera.capture"
        title: qsTr("Take a photo or video to return")
        description: "Ask the person for one photo or video: brings Marathon Camera to the front on its viewfinder in that mode, waits for the person to take it, then answers with the saved file's path (under ~/Pictures/Marathon) and goes away, back to whatever was in front. Fails with Cancelled when the person leaves the camera without taking one, or another capture is asked for; with NotAvailable when the device has no camera; with Timeout after 10 minutes."
        timeout: 600000
        parameters: [
            KeelParam { name: "mode"; type: "string"; values: ["photo", "video"]; defaultValue: "photo" }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "path"; type: "string"; maxLength: 4096; required: true; description: "The photo or video, an absolute path" }
            KeelParam { name: "mode"; type: "string"; values: ["photo", "video"]; required: true }
        }
        onInvoked: (args, call) => {
            const app = root.app;
            if (app.camera.discovered && app.camera.cameraCount === 0) {
                call.fail("NotAvailable", "this device has no camera");
                return;
            }
            app.beginCapture(call, args.mode || "photo");
        }
    }

    KeelAction {
        name: "camera.open"
        title: qsTr("Open camera")
        description: "Bring Marathon Camera to the front for the person, on its viewfinder in photo or video mode, ready to shoot. It takes no photo itself. While a video is recording the mode stays as it is. Fails with NotAvailable when the device has no camera. Returns the mode the camera is in."
        idempotent: true
        parameters: [
            KeelParam { name: "mode"; type: "string"; values: ["photo", "video"]; defaultValue: "photo" }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "mode"; type: "string"; values: ["photo", "video"]; required: true }
        }
        onInvoked: (args, call) => {
            const app = root.app;
            // Cameras are only enumerated once the camera first starts.
            if (app.camera.discovered && app.camera.cameraCount === 0) {
                call.fail("NotAvailable", "this device has no camera");
                return;
            }
            app.setMode(args.mode || "photo");
            if (app.pageStack.depth > 1)
                app.pageStack.pop();
            app.activate();
            call.reply({ mode: app.mode });
        }
    }
}
