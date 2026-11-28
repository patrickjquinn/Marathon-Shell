import QtQuick
import QtQuick.Window
import QtTest
import "../../shell/qml/keyboard/UI"

// The keyboard's touch layer, with real touches: two thumbs, gaps between
// keys, swipes and the space and backspace slides.
TestCase {
    name: "KeyboardTouch"
    when: windowShown

    property var typed: []

    Window {
        id: window

        width: 400
        height: 200
        visible: true

        Item {
            id: keys

            anchors.fill: parent

            Row {
                y: 10
                spacing: 4

                Repeater {
                    model: ["q", "w", "e", "r", "t"]

                    Key {
                        required property string modelData

                        width: 60
                        text: modelData
                        onClicked: typed.push(modelData)
                    }
                }
            }

            Row {
                y: 110
                spacing: 4

                Key {
                    id: space

                    width: 200
                    text: " "
                    isSpecial: true
                    onClicked: typed.push(" ")
                }

                Key {
                    id: backspace

                    width: 100
                    text: "backspace"
                    isSpecial: true
                    autoRepeat: true
                    onClicked: typed.push("<")
                }
            }
        }

        KeyboardTouch {
            id: touch

            anchors.fill: parent
            layout: keys
        }
    }

    SignalSpy {
        id: swipeSpy

        target: touch
        signalName: "swiped"
    }

    SignalSpy {
        id: cursorSpy

        target: touch
        signalName: "cursorStep"
    }

    SignalSpy {
        id: deleteSpy

        target: touch
        signalName: "deleteWords"
    }

    SignalSpy {
        id: lettersSpy

        target: touch
        signalName: "lettersMoved"
    }

    function init() {
        typed = [];
        swipeSpy.clear();
        cursorSpy.clear();
        deleteSpy.clear();
        touch.swipeEnabled = true;
    }

    // The centre of letter key i, in the touch layer.
    function letter(i) {
        return Qt.point(30 + i * 64, 10 + 45);
    }

    function test_aTapTypesItsKey() {
        const p = letter(2);
        touchEvent(touch).press(0, touch, p.x, p.y).commit();
        touchEvent(touch).release(0, touch, p.x, p.y).commit();
        compare(typed, ["e"]);
        verify(lettersSpy.count > 0);
        verify(lettersSpy.signalArguments[lettersSpy.count - 1][0].startsWith("q 30.0"));
    }

    function test_twoThumbsOverlappingTypeBothInOrder() {
        const a = letter(0);
        const b = letter(3);
        // A finger held still is reported where it is.
        touchEvent(touch).press(0, touch, a.x, a.y).commit();
        touchEvent(touch).move(0, touch, a.x, a.y).press(1, touch, b.x, b.y).commit();
        compare(typed, ["q"]);
        touchEvent(touch).release(0, touch, a.x, a.y).move(1, touch, b.x, b.y).commit();
        touchEvent(touch).release(1, touch, b.x, b.y).commit();
        compare(typed, ["q", "r"]);
    }

    function test_aTouchBetweenKeysIsTheNearestKeys() {
        // The 4 px gap between w (64-124) and e (128-188), nearer e.
        touchEvent(touch).press(0, touch, 127, 55).commit();
        touchEvent(touch).release(0, touch, 127, 55).commit();
        compare(typed, ["e"]);
    }

    function test_slidingAcrossLettersSwipes() {
        const a = letter(0);
        const b = letter(4);
        let seq = touchEvent(touch).press(0, touch, a.x, a.y);
        seq.commit();
        for (let x = a.x + 10; x <= b.x; x += 10)
            touchEvent(touch).move(0, touch, x, a.y).commit();
        touchEvent(touch).release(0, touch, b.x, b.y).commit();
        compare(typed, []);
        compare(swipeSpy.count, 1);
        verify(swipeSpy.signalArguments[0][0].split(";").length > 5);
    }

    function test_withoutSwipingASlideMovesTheKey() {
        touch.swipeEnabled = false;
        const a = letter(0);
        const b = letter(1);
        touchEvent(touch).press(0, touch, a.x, a.y).commit();
        touchEvent(touch).move(0, touch, b.x, b.y).commit();
        touchEvent(touch).release(0, touch, b.x, b.y).commit();
        compare(typed, ["w"]);
        compare(swipeSpy.count, 0);
    }

    function test_slidingAlongSpaceMovesTheCursor() {
        touchEvent(touch).press(0, touch, 100, 150).commit();
        for (let x = 95; x >= 20; x -= 5)
            touchEvent(touch).move(0, touch, x, 150).commit();
        touchEvent(touch).release(0, touch, 20, 150).commit();
        compare(typed, []);
        verify(cursorSpy.count >= 2);
        compare(cursorSpy.signalArguments[0][0], -1);
    }

    function test_slidingLeftOffBackspaceDeletesWords() {
        touchEvent(touch).press(0, touch, 254, 150).commit();
        for (let x = 250; x >= 100; x -= 10)
            touchEvent(touch).move(0, touch, x, 150).commit();
        touchEvent(touch).release(0, touch, 100, 150).commit();
        compare(typed, []);
        compare(deleteSpy.count, 1);
        verify(deleteSpy.signalArguments[0][0] >= 2);
    }
}
