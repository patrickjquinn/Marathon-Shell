import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "Dialer"
    when: windowShown
    visible: true
    width: 720
    height: 1440

    QtObject {
        id: seenStub

        property var value: 0
    }
    Component {
        id: appComponent

        PhoneApp {
            width: 720
            height: 1440
        }
    }

    function init() {
        Telephony.reset();
        Contacts.reset();
        CallHistory.reset();
        Permissions.reset();
    }

    function makeApp(props) {
        const app = createTemporaryObject(appComponent, testCase, Object.assign({ callLogSeen: seenStub }, props || {}));
        tryVerify(() => app.pageStack.currentPage !== null);
        return app;
    }

    function dialer(app) {
        let d = null;
        tryVerify(() => (d = findChild(app.pageStack.currentPage, "keypad")) !== null);
        return d;
    }

    function type(app, digits) {
        const keypad = dialer(app);
        for (const d of digits)
            keypad.clicked(d);
    }

    function test_keypadBuildsNumber() {
        const app = makeApp();
        type(app, "0871");
        compare(app.dialedNumber, "0871");
        compare(findChild(app.pageStack.currentPage, "numberLabel").text, "0871");
        findChild(app.pageStack.currentPage, "backspaceButton").clicked(null);
        compare(app.dialedNumber, "087");
    }

    function test_holdZeroForPlus() {
        const app = makeApp();
        const keypad = dialer(app);
        keypad.pressAndHold("0", null);
        keypad.clicked("0");
        keypad.clicked("1");
        compare(app.dialedNumber, "+1");
    }

    function test_callDialsAndShowsCallPage() {
        Contacts.contacts = [{ id: 1, name: "Ada", phone: "+1 555 123 4567" }];
        const app = makeApp();
        type(app, "5551234567");
        compare(findChild(app.pageStack.currentPage, "matchLabel").text, "Ada");
        findChild(app.pageStack.currentPage, "callButton").clicked(null);
        compare(Telephony.log, ["dial:5551234567"]);
        compare(app.callName, "Ada");
        tryVerify(() => app.callPage !== null && app.pageStack.currentPage === app.callPage);
    }

    function test_callButtonDisabledWhenEmpty() {
        const app = makeApp();
        dialer(app);
        verify(!findChild(app.pageStack.currentPage, "callButton").enabled);
    }

    function test_emergencyNumberUsesEmergencyDial() {
        const app = makeApp();
        type(app, "112");
        const button = findChild(app.pageStack.currentPage, "callButton");
        compare(button.text, "Emergency call");
        button.clicked(null);
        compare(Telephony.log, ["emergency:112"]);
        compare(app.callName, "Emergency call");
    }

    function test_emergencyRouteShowsOnlyDialer() {
        const app = makeApp({ route: "/emergency" });
        verify(app.emergencyOnly);
        dialer(app);
        verify(findChild(app.pageStack.currentPage, "dialer") !== null);
        verify(findChild(app.pageStack.currentPage, "people") === null);
        compare(app.contacts.length, 0);
        app.requestContacts();
        compare(Permissions.requests, []);
    }

    function test_emergencyRouteAlwaysDialsEmergency() {
        const app = makeApp({ route: "/emergency" });
        type(app, "5551234");
        findChild(app.pageStack.currentPage, "callButton").clicked(null);
        compare(Telephony.log, ["emergency:5551234"]);
    }

    function test_idleClosesCallPage() {
        const app = makeApp();
        type(app, "5551234");
        findChild(app.pageStack.currentPage, "callButton").clicked(null);
        tryVerify(() => app.pageStack.currentPage === app.callPage && !app.pageStack.busy);
        Telephony.setState("active");
        Telephony.setState("idle");
        tryVerify(() => app.pageStack.depth === 1 && !app.pageStack.busy);
        compare(app.dialedNumber, "");
        verify(app.callPage === null);
    }

    function test_callFailedClosesCallPage() {
        const app = makeApp();
        type(app, "5551234");
        findChild(app.pageStack.currentPage, "callButton").clicked(null);
        tryVerify(() => !app.pageStack.busy);
        Telephony.callFailed("No modem available");
        tryVerify(() => app.pageStack.depth === 1 && !app.pageStack.busy);
    }
}
