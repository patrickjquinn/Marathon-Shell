import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    property Item page: null

    name: "OOBEPasscode"
    when: windowShown

    Window {
        id: win

        width: 720
        height: 720
        visible: true

        MarathonOOBE {
            id: oobe
        }
    }

    function init() {
        SecurityManagerCpp.firstRunPins = [];
        oobe.currentPage = 0;
        win.requestActivate();
        tryVerify(() => win.active);
        oobe.currentPage = 5;
    }

    // The step that holds keyboard focus once the wizard reaches it.
    function passcodePage() {
        tryVerify(() => win.activeFocusItem !== null);
        tc.page = win.activeFocusItem;
        return tc.page;
    }

    function cleanup() {
        if (!tc.page)
            return;
        tc.page.stage = "enter";
        tc.page.enteredPin = "";
        tc.page.confirmedPin = "";
    }

    function test_focusLandsOnPasscodeStep() {
        const page = passcodePage();
        compare(page.stage, "enter");
    }

    function test_digitsOnlyReachThePasscodeStep() {
        const page = passcodePage();
        oobe.currentPage = 4;
        verify(!page.activeFocus);
        keyClick(Qt.Key_1);
        oobe.currentPage = 5;
        compare(page.enteredPin, "");
        verify(page.activeFocus);
    }

    function test_typedDigitsSetPasscode() {
        const page = passcodePage();
        for (const d of "1234")
            keyClick(Qt.Key_0 + Number(d));
        compare(page.enteredPin, "1234");
        keyClick(Qt.Key_Backspace);
        compare(page.enteredPin, "123");
        keyClick(Qt.Key_Return);
        compare(page.stage, "enter");
        for (const d of "456")
            keyClick(Qt.Key_0 + Number(d));
        compare(page.stage, "confirm");
        for (const d of "123456")
            keyClick(Qt.Key_0 + Number(d));
        compare(SecurityManagerCpp.firstRunPins, ["123456"]);
        compare(oobe.currentPage, 6);
    }
}
