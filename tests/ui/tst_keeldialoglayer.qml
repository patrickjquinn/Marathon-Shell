import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: testCase

    name: "KeelDialogLayer"
    when: windowShown

    Window {
        width: 360
        height: 640
        visible: true

        Rectangle {
            id: app

            anchors.fill: parent
            color: "red"
        }

        KeelDialogLayer {
            id: layer

            anchors.fill: parent
            anchors.topMargin: 40
        }
    }

    // WaylandCompositor's back and forward, recorded.
    QtObject {
        id: compositor

        property var marathonSurfaces: ({})
        property var backs: []
        property var forwards: []

        signal nativeBackUnhandled(int surfaceId)

        function sendNativeBack(surfaceId, keelHosted) {
            backs = backs.concat([surfaceId]);
        }
        function sendNativeForward(surfaceId, keelHosted) {
            forwards = forwards.concat([surfaceId]);
        }
    }

    Component {
        id: xdgSurface

        // A drawn toplevel that counts the compositor's close requests.
        QtObject {
            property QtObject surface: QtObject {
                property bool hasContent: true
            }
            property QtObject toplevel: QtObject {
                property int closes: 0
                property string title: "keel:dialog"

                function sendClose() {
                    closes++;
                }
            }
        }
    }

    function cleanup() {
        for (const d of layer.dialogs.slice())
            layer._remove(d);
        layer._showing = false;
        layer.backdropSource = null;
        layer.compositor = null;
        compositor.marathonSurfaces = {};
        compositor.backs = [];
        compositor.forwards = [];
    }

    function dialog(surfaceId) {
        const xdg = createTemporaryObject(xdgSurface, testCase);
        layer.add("shoal-pilot", xdg, surfaceId);
        tryVerify(() => layer.front() !== null);
        return xdg;
    }

    function test_backAndForwardPassWithoutADialog() {
        layer.compositor = compositor;
        verify(!layer.back());
        verify(!layer.forward());
        compare(compositor.backs.length, 0);
    }

    // Back over an app with Pilot's overlay up closes the overlay, and
    // only it: the shell's back stops here.
    function test_backClosesTheDialogNotTheAppUnderIt() {
        layer.compositor = compositor;
        const xdg = dialog(7);
        verify(layer.back());
        compare(xdg.toplevel.closes, 1);
        compare(compositor.backs.length, 0);
        verify(layer.forward());
        compare(compositor.forwards, [7]);
    }

    // A runner's dialog handles back itself, and is closed if it doesn't.
    function test_aRunnersDialogTakesBackFirst() {
        layer.compositor = compositor;
        compositor.marathonSurfaces = {
            "7": true
        };
        const xdg = dialog(7);
        verify(layer.back());
        compare(compositor.backs, [7]);
        compare(xdg.toplevel.closes, 0);
        compositor.nativeBackUnhandled(7);
        compare(xdg.toplevel.closes, 1);
    }

    // An app's own modal window shows over that app only.
    function test_anAppsDialogShowsOnlyOverItsApp() {
        const xdg = createTemporaryObject(xdgSurface, testCase);
        xdg.toplevel.title = "Add Account";
        UIStore.appWindowOpen = true;
        UIStore.currentAppId = "dev.geopjr.Tuba";
        layer.add("dev.geopjr.Tuba", xdg, 9);
        tryVerify(() => layer.front() !== null);
        UIStore.currentAppId = "de.haeckerfelix.Shortwave";
        tryVerify(() => layer.front() === null);
        UIStore.appWindowOpen = false;
        UIStore.currentAppId = "";
    }

    function test_hiddenWithoutADialog() {
        verify(!findChild(layer, "keelDialogBackdrop").visible);
    }

    function test_dimsTheAppBehind() {
        layer.backdropSource = app;
        layer._showing = true;
        tryCompare(findChild(layer, "keelDialogBackdrop"), "opacity", 1);
        verify(findChild(layer, "keelDialogDim").visible);
    }

    function test_ambienceOverHome() {
        layer.backdropSource = null;
        layer._showing = true;
        tryCompare(findChild(layer, "keelDialogBackdrop"), "opacity", 1);
        verify(!findChild(layer, "keelDialogDim").visible);
    }
}
