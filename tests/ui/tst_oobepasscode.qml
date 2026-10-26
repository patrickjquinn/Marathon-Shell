import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components/oobe"

TestCase {
    id: tc

    name: "OobePasscode"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        OobePasscode {
            id: beat

            anchors.fill: parent
        }
    }

    SignalSpy {
        id: doneSpy

        target: beat
        signalName: "done"
    }

    function init() {
        Security.firstRunPins = [];
        Security.hasQuickPIN = false;
        doneSpy.clear();
        beat.reset();
        win.requestActivate();
        tryVerify(() => win.active);
        beat.forceActiveFocus();
    }

    function pad(digits) {
        const keypad = findChild(beat, "oobeKeypad");
        for (const d of digits)
            keypad.clicked(d);
    }

    function filledDots() {
        let n = 0;
        for (let i = 0; i < 6; i++)
            if (findChild(beat, "oobeDot" + i).filled)
                n++;
        return n;
    }

    function test_keypadDigitsFillDotsAndDeleteRemoves() {
        pad("123");
        compare(filledDots(), 3);
        mouseClick(findChild(beat, "oobeDelete"));
        compare(filledDots(), 2);
        compare(beat.enteredPin, "12");
    }

    function test_deleteKeySitsBesideZero() {
        const keypad = findChild(beat, "oobeKeypad");
        const del = findChild(beat, "oobeDelete");
        verify(del.visible);
        const p = del.mapToItem(keypad, del.width / 2, del.height / 2);
        verify(p.y > keypad.height * 0.75 && p.y < keypad.height);
        verify(p.x > keypad.width * 0.6);
    }

    function test_mismatchShowsMessageAndClearsConfirm() {
        pad("123456");
        compare(beat.stage, "confirm");
        pad("654321");
        compare(beat.confirmedPin, "");
        compare(findChild(beat, "oobeError").text, "Passcodes don't match. Try again.");
        compare(Security.firstRunPins, []);
        compare(doneSpy.count, 0);
    }

    function test_matchSavesAndAdvances() {
        pad("123456");
        pad("123456");
        compare(Security.firstRunPins, ["123456"]);
        compare(doneSpy.count, 1);
    }

    function test_refusedSaveShowsErrorAndStays() {
        Security.hasQuickPIN = true;
        pad("123456");
        pad("123456");
        compare(Security.firstRunPins, []);
        compare(findChild(beat, "oobeError").text, "Couldn't save the passcode. Try again.");
        compare(beat.stage, "enter");
        compare(doneSpy.count, 0);
    }

    function test_backOnConfirmReturnsToEnterAndClears() {
        pad("123456");
        pad("12");
        verify(beat.handleBack());
        compare(beat.stage, "enter");
        compare(beat.enteredPin, "");
        compare(beat.confirmedPin, "");
    }

    function test_backMidEntryClearsDigitsAndLeaves() {
        pad("123");
        verify(!beat.handleBack());
        compare(beat.enteredPin, "");
    }

    function test_leavingClearsDigits() {
        pad("123456");
        beat.visible = false;
        beat.visible = true;
        compare(beat.stage, "enter");
        compare(beat.enteredPin, "");
    }

    function test_physicalKeys() {
        for (const d of "1234")
            keyClick(Qt.Key_0 + Number(d));
        compare(beat.enteredPin, "1234");
        keyClick(Qt.Key_Backspace);
        compare(beat.enteredPin, "123");
        keyClick(Qt.Key_Return);
        compare(beat.stage, "enter");
        for (const d of "456")
            keyClick(Qt.Key_0 + Number(d));
        compare(beat.stage, "confirm");
        for (const d of "123456")
            keyClick(Qt.Key_0 + Number(d));
        compare(Security.firstRunPins, ["123456"]);
        compare(doneSpy.count, 1);
    }
}
