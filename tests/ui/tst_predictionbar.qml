import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import "../../shell/qml/keyboard/UI"

TestCase {
    name: "PredictionBar"
    when: windowShown

    Window {
        width: 360
        height: 100
        visible: true

        PredictionBar {
            id: bar

            width: 360
        }
    }

    SignalSpy {
        id: pasteSpy

        target: bar
        signalName: "pasteRequested"
    }

    function init() {
        pasteSpy.clear();
        bar.predictions = [];
    }

    function test_pasteOffersTheClipboard() {
        Silica.Clipboard.text = "my wifi password";
        const chip = findChild(bar, "pasteChip");
        verify(bar.visible);
        verify(chip.visible);
        mouseClick(chip);
        compare(pasteSpy.count, 1);
        compare(pasteSpy.signalArguments[0][0], "my wifi password");
    }

    function test_noPasteWithAnEmptyClipboard() {
        Silica.Clipboard.text = "";
        verify(!findChild(bar, "pasteChip").visible);
        verify(!bar.visible);
    }

    function test_predictionsMakeRoomForPaste() {
        Silica.Clipboard.text = "x";
        bar.predictions = ["one", "two", "three"];
        const chip = findChild(bar, "pasteChip");
        verify(chip.visible);
        verify(bar.visible);
        mouseClick(chip);
        compare(pasteSpy.count, 1);
    }
}
