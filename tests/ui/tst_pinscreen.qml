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
    }

    function init() {
        SecurityManagerCpp.attempts = [];
        SecurityManagerCpp.isLockedOut = false;
        SecurityManagerCpp.lockoutStateChanged();
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
        compare(SecurityManagerCpp.attempts.length, 0);
        const accept = findChild(pinScreen, "acceptKey");
        verify(accept);
        verify(!accept.disabled);
        mouseClick(accept);
        compare(SecurityManagerCpp.attempts, ["1234"]);
    }

    function test_returnSubmitsFiveDigits() {
        type("12345");
        keyClick(Qt.Key_Return);
        compare(SecurityManagerCpp.attempts, ["12345"]);
    }

    function test_acceptNeedsFourDigits() {
        type("123");
        verify(findChild(pinScreen, "acceptKey").disabled);
        keyClick(Qt.Key_Return);
        compare(SecurityManagerCpp.attempts.length, 0);
    }

    function test_sixDigitsStillSubmitOnce() {
        type("123456");
        tryCompare(SecurityManagerCpp, "attempts", ["123456"]);
        keyClick(Qt.Key_Return);
        compare(SecurityManagerCpp.attempts.length, 1);
    }

    function test_errorStaysUntilNextDigit() {
        type("123456");
        tryCompare(SecurityManagerCpp, "attempts", ["123456"]);
        SecurityManagerCpp.authenticationFailed("Incorrect PIN (3 attempts remaining)");
        compare(pinScreen.pin, "");
        wait(1500);
        compare(pinScreen.error, "Incorrect PIN (3 attempts remaining)");
        type("1");
        compare(pinScreen.error, "");
    }

    function test_lockoutDisablesKeypadAndCountsDown() {
        SecurityManagerCpp.lockoutSecondsRemaining = 30;
        SecurityManagerCpp.isLockedOut = true;
        SecurityManagerCpp.lockoutStateChanged();
        verify(pinScreen.error.indexOf("30") >= 0);
        verify(findChild(pinScreen, "key1").disabled);
        verify(findChild(pinScreen, "key0").disabled);
        type("1");
        compare(pinScreen.pin, "");
        SecurityManagerCpp.lockoutSecondsRemaining = 29;
        SecurityManagerCpp.lockoutStateChanged();
        verify(pinScreen.error.indexOf("29") >= 0);
        SecurityManagerCpp.isLockedOut = false;
        SecurityManagerCpp.lockoutStateChanged();
        compare(pinScreen.error, "");
        verify(!findChild(pinScreen, "key1").disabled);
    }
}
