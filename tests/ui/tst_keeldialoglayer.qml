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

    function cleanup() {
        layer._showing = false;
        layer.backdropSource = null;
    }

    function test_hiddenWithoutADialog() {
        verify(!findChild(layer, "keelDialogBackdrop").visible);
    }

    function test_frostsTheAppAtQuarterResolution() {
        layer.backdropSource = app;
        layer._showing = true;
        const backdrop = findChild(layer, "keelDialogBackdrop");
        tryCompare(backdrop, "opacity", 1);
        const snapshot = findChild(layer, "keelDialogSnapshot");
        compare(snapshot.sourceItem, app);
        verify(!snapshot.live);
        compare(snapshot.textureSize, Qt.size(90, 150));
        compare(snapshot.sourceRect, Qt.rect(0, 40, 360, 600));
    }

    function test_noCaptureOverHome() {
        layer._showing = true;
        tryCompare(findChild(layer, "keelDialogBackdrop"), "opacity", 1);
        compare(findChild(layer, "keelDialogSnapshot").sourceItem, null);
    }
}
