import QtQuick
import QtQuick.Window
import QtTest
import "../../shell/qml/ui"

TestCase {
    name: "MQSTile"
    when: windowShown

    Window {
        width: 360
        height: 360
        visible: true

        MQSTile {
            id: tile
            label: "Wi-Fi"
            iconName: "wifi-high"
        }
    }

    SignalSpy {
        id: heldSpy
        target: tile
        signalName: "held"
    }
    SignalSpy {
        id: toggledSpy
        target: tile
        signalName: "toggled"
    }

    function init() {
        heldSpy.clear();
        toggledSpy.clear();
        tile.on = false;
        tile.busy = false;
    }

    function test_busyPulsesTheRing() {
        const ring = findChild(tile, "ring");
        verify(ring);
        const idle = ring.border.color.toString();
        tile.busy = true;
        const pulse = findChild(tile, "busyPulse");
        verify(pulse.running, "busy pulse runs");
        tryVerify(() => ring.border.color.toString() !== idle, 1000, "busy ring differs from idle");
    }

    function test_busyStopsWhenResolved() {
        tile.busy = true;
        tile.busy = false;
        verify(!findChild(tile, "busyPulse").running);
    }

    function test_busyDoesNotFill() {
        const ring = findChild(tile, "ring");
        const idleFill = ring.color.toString();
        tile.busy = true;
        compare(ring.color.toString(), idleFill);
    }

    function test_longPressHoldsWithoutToggling() {
        mousePress(tile, tile.width / 2, tile.height / 2);
        tryCompare(heldSpy, "count", 1, 2000);
        mouseRelease(tile, tile.width / 2, tile.height / 2);
        compare(toggledSpy.count, 0);
    }
}
