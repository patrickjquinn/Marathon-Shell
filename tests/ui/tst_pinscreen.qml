import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "PinScreen"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        MarathonPinScreen {
            id: pinScreen
        }

        Text {
            id: sibling

            text: "shell"
        }
    }

    function init() {
        Security.attempts = [];
        Security.isLockedOut = false;
        Security.lockoutStateChanged();
        pinScreen.authenticating = false;
        win.requestActivate();
        tryVerify(() => win.active);
        pinScreen.show();
    }

    function type(digits) {
        for (const d of digits)
            pinScreen.handleInput(d);
    }

    function test_fourDigitPinSubmitsWithAccept() {
        type("1234");
        wait(200);
        compare(Security.attempts.length, 0);
        const accept = findChild(pinScreen, "acceptKey");
        verify(accept);
        verify(!accept.disabled);
        mouseClick(accept);
        compare(Security.attempts, ["1234"]);
    }

    function test_returnSubmitsFiveDigits() {
        type("12345");
        keyClick(Qt.Key_Return);
        compare(Security.attempts, ["12345"]);
    }

    function test_acceptNeedsFourDigits() {
        type("123");
        verify(findChild(pinScreen, "acceptKey").disabled);
        keyClick(Qt.Key_Return);
        compare(Security.attempts.length, 0);
    }

    function test_sixDigitsStillSubmitOnce() {
        type("123456");
        tryCompare(Security, "attempts", ["123456"]);
        keyClick(Qt.Key_Return);
        compare(Security.attempts.length, 1);
    }

    function test_errorStaysUntilNextDigit() {
        type("123456");
        tryCompare(Security, "attempts", ["123456"]);
        Security.authenticationFailed("Incorrect PIN (3 attempts remaining)");
        compare(pinScreen.pin, "");
        wait(1500);
        compare(pinScreen.error, "Incorrect PIN (3 attempts remaining)");
        type("1");
        compare(pinScreen.error, "");
    }

    function test_lockoutDisablesKeypadAndCountsDown() {
        Security.lockoutSecondsRemaining = 30;
        Security.isLockedOut = true;
        Security.lockoutStateChanged();
        verify(pinScreen.error.indexOf("30") >= 0);
        verify(findChild(pinScreen, "key1").disabled);
        verify(findChild(pinScreen, "key0").disabled);
        type("1");
        compare(pinScreen.pin, "");
        Security.lockoutSecondsRemaining = 29;
        Security.lockoutStateChanged();
        verify(pinScreen.error.indexOf("29") >= 0);
        Security.isLockedOut = false;
        Security.lockoutStateChanged();
        compare(pinScreen.error, "");
        verify(!findChild(pinScreen, "key1").disabled);
    }

    function test_errorDoesNotMoveKeypad() {
        const key = findChild(pinScreen, "key1");
        const before = key.mapToItem(null, 0, 0).y;
        Security.authenticationFailed("Incorrect PIN (3 attempts remaining)");
        waitForRendering(pinScreen);
        compare(key.mapToItem(null, 0, 0).y, before);
        type("1");
        waitForRendering(pinScreen);
        compare(key.mapToItem(null, 0, 0).y, before);
    }

    function test_titleFollowsMode() {
        const title = findChild(pinScreen, "pinTitle");
        compare(title.text, "Enter PIN");
        pinScreen.switchToPasswordMode();
        wait(50);
        compare(sibling.opacity, 1);
        tryCompare(title, "text", "Enter password");
        compare(sibling.text, "shell");
        pinScreen.switchToPINMode();
        tryCompare(title, "text", "Enter PIN");
    }
}
