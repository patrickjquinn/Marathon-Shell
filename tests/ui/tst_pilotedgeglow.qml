import QtQuick
import QtQuick.Window
import QtTest
import "../../shell/qml/components"

TestCase {
    name: "PilotEdgeGlow"
    when: windowShown

    Window {
        width: 360
        height: 720
        visible: true

        PilotEdgeGlow {
            id: glow
            anchors.fill: parent
        }

        MouseArea {
            id: under
            anchors.fill: parent
            z: -1
        }
    }

    SignalSpy { id: clicks; target: under; signalName: "clicked" }

    function init() {
        glow.lit = false;
        tryVerify(() => !glow.visible);
        clicks.clear();
    }

    function test_lightsAndFadesAfterThreeSeconds() {
        verify(!glow.visible);
        glow.light();
        verify(glow.lit);
        wait(2500);
        compare(glow.opacity, 1);
        tryVerify(() => !glow.visible, 2000);
    }

    function test_fadesWhenTheOverlayShows() {
        glow.light();
        wait(100);
        glow.overlayShown();
        tryVerify(() => !glow.visible, 1500);
    }

    function test_overlayAloneDoesNotLight() {
        glow.overlayShown();
        wait(500);
        verify(!glow.visible);
    }

    function test_takesNoInput() {
        glow.light();
        mouseClick(glow, glow.width / 2, 5);
        mouseClick(glow, 5, glow.height / 2);
        compare(clicks.count, 2);
    }

    function test_fourEdges() {
        let bands = 0;
        for (let i = 0; i < glow.children.length; ++i) {
            const c = glow.children[i];
            if (c.gradient === undefined)
                continue;
            ++bands;
            verify(c.width === glow.band || c.height === glow.band);
        }
        compare(bands, 4);
    }
}
