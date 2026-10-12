import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import "../../shell/qml/keyboard/UI"

TestCase {
    name: "KeyboardKey"
    when: windowShown

    Window {
        width: 360
        height: 720
        visible: true

        Key {
            id: key
            x: 160
            y: 400
            width: 36
            text: "a"
            alternateChars: ["à", "á", "â"]
        }

        Key {
            id: shiftKey
            x: 20
            y: 400
            width: 54
            text: "shift"
            iconName: "chevron-up"
            isSpecial: true
        }
    }

    SignalSpy { id: clickedSpy; target: key; signalName: "clicked" }
    SignalSpy { id: alternateSpy; target: key; signalName: "alternateSelected" }
    SignalSpy { id: holdSpy; target: key; signalName: "pressAndHold" }

    function init() {
        key.alternateChars = ["à", "á", "â"];
        key.isSpecial = false;
        key.autoRepeat = false;
        key.consumesHold = false;
        clickedSpy.clear();
        alternateSpy.clear();
        holdSpy.clear();
    }

    function cleanup() {
        if (key.pressed)
            mouseRelease(key, 0, 0);
    }

    function alternateCentre(i) {
        const cell = findChild(key, "alternate_" + i);
        verify(cell, "alternate cell " + i);
        return cell.mapToItem(key, cell.width / 2, cell.height / 2);
    }

    function longPress() {
        mousePress(key, key.width / 2, key.height / 2);
        tryCompare(key, "showingAlternates", true, 1000);
    }

    function test_tapCommitsBaseKey() {
        mouseClick(key, key.width / 2, key.height / 2);
        compare(clickedSpy.count, 1);
        compare(alternateSpy.count, 0);
    }

    function test_slideToAlternateAndReleaseCommitsIt() {
        longPress();
        const p = alternateCentre(2);
        mouseMove(key, p.x, p.y, -1, Qt.LeftButton);
        verify(findChild(key, "alternate_2").selected);
        verify(!findChild(key, "alternate_0").selected);
        mouseRelease(key, p.x, p.y);
        compare(alternateSpy.count, 1);
        compare(alternateSpy.signalArguments[0][0], "â");
        compare(clickedSpy.count, 0);
        verify(!key.showingAlternates);
    }

    function test_slideAcrossMovesHighlight() {
        longPress();
        let p = alternateCentre(0);
        mouseMove(key, p.x, p.y, -1, Qt.LeftButton);
        verify(findChild(key, "alternate_0").selected);
        p = alternateCentre(1);
        mouseMove(key, p.x, p.y, -1, Qt.LeftButton);
        verify(findChild(key, "alternate_1").selected);
        verify(!findChild(key, "alternate_0").selected);
        mouseRelease(key, p.x, p.y);
        compare(alternateSpy.signalArguments[0][0], "á");
    }

    function test_releaseWithoutSlidingCommitsBaseKey() {
        longPress();
        mouseRelease(key, key.width / 2, key.height / 2);
        compare(clickedSpy.count, 1);
        compare(alternateSpy.count, 0);
        verify(!key.showingAlternates);
    }

    function test_holdOnKeyWithoutAlternatesFiresPressAndHold() {
        key.alternateChars = [];
        key.isSpecial = true;
        key.consumesHold = true;
        mousePress(key, key.width / 2, key.height / 2);
        tryCompare(holdSpy, "count", 1, 1000);
        mouseRelease(key, key.width / 2, key.height / 2);
        compare(clickedSpy.count, 0);
    }

    function test_holdOnPlainKeyStillTypesIt() {
        key.alternateChars = [];
        mousePress(key, key.width / 2, key.height / 2);
        tryCompare(holdSpy, "count", 1, 1000);
        mouseRelease(key, key.width / 2, key.height / 2);
        compare(clickedSpy.count, 1);
    }

    function test_heldSpecialKeyWithoutHoldActionStillTypes() {
        key.alternateChars = [];
        key.isSpecial = true;
        mousePress(key, key.width / 2, key.height / 2);
        tryCompare(holdSpy, "count", 1, 1000);
        mouseRelease(key, key.width / 2, key.height / 2);
        compare(clickedSpy.count, 1);
    }

    function test_autoRepeatWhileHeld() {
        key.alternateChars = [];
        key.isSpecial = true;
        key.autoRepeat = true;
        key.consumesHold = true;
        mousePress(key, key.width / 2, key.height / 2);
        wait(400);
        compare(clickedSpy.count, 0);
        tryVerify(() => clickedSpy.count >= 4, 1500);
        mouseRelease(key, key.width / 2, key.height / 2);
        const n = clickedSpy.count;
        wait(250);
        compare(clickedSpy.count, n);
    }

    // The test theme's highlight and primary colours are both white, so
    // this checks the bindings rather than a visible difference.
    function test_highlightedShiftShowsItsState() {
        const glyph = findChild(shiftKey, "keyGlyph");
        verify(glyph);
        shiftKey.highlighted = true;
        verify(Qt.colorEqual(glyph.color, Silica.Theme.highlightColor));
        shiftKey.highlighted = false;
        verify(Qt.colorEqual(glyph.color, Silica.Theme.primaryColor));
    }
}
