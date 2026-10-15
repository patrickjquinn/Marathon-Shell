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
    Component {
        id: squareAppComponent

        PhoneApp {
            width: 720
            height: 658
        }
    }

    function init() {
        Telephony.reset();
        Contacts.reset();
        CallHistory.reset();
        Permissions.reset();
    }

    function makeApp(props, component) {
        const app = createTemporaryObject(component || appComponent, testCase, Object.assign({ callLogSeen: seenStub }, props || {}));
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

    function test_emptyCallRecallsLastDialled() {
        CallHistory.history = [
            { id: 1, number: "0871111111", type: "outgoing", timestamp: 1700000000 },
            { id: 2, number: "0872222222", type: "incoming", timestamp: 1700000300 },
            { id: 3, number: "0873333333", type: "outgoing", timestamp: 1700000200 }
        ];
        const app = makeApp();
        dialer(app);
        const button = findChild(app.pageStack.currentPage, "callButton");
        verify(button.enabled);
        button.clicked(null);
        compare(app.dialedNumber, "0873333333");
        compare(Telephony.log, []);
        button.clicked(null);
        compare(Telephony.log, ["dial:0873333333"]);
    }

    function test_noRecallWithoutModem() {
        Telephony.hasModem = false;
        CallHistory.history = [{ id: 1, number: "0871111111", type: "outgoing", timestamp: 1700000000 }];
        const app = makeApp();
        dialer(app);
        verify(!findChild(app.pageStack.currentPage, "callButton").enabled);
    }

    function test_holdNumberToPaste() {
        const app = makeApp();
        type(app, "00");
        Clipboard.text = "tel: +353 (87) 123-4567";
        const page = app.pageStack.currentPage;
        findChild(page, "numberArea").pressAndHold(null);
        let item = null;
        tryVerify(() => (item = findChild(page, "pasteMenuItem")) !== null && item.visible);
        item.clicked();
        compare(app.dialedNumber, "00+353871234567");
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

    function test_noModemSaysSoUpFront() {
        Telephony.hasModem = false;
        const app = makeApp();
        dialer(app);
        const page = app.pageStack.currentPage;
        compare(findChild(page, "numberLabel").text, "No SIM or modem");
        type(app, "5551234");
        verify(!findChild(page, "callButton").enabled);
        compare(findChild(page, "matchLabel").text, "Calls aren't available");
    }

    function test_noModemStillAllowsEmergencyNumbers() {
        Telephony.hasModem = false;
        const app = makeApp();
        type(app, "112");
        const button = findChild(app.pageStack.currentPage, "callButton");
        verify(button.enabled);
        button.clicked(null);
        compare(Telephony.log, ["emergency:112"]);
    }

    function test_noModemEmergencyRouteStaysEnabled() {
        Telephony.hasModem = false;
        const app = makeApp({ route: "/emergency" });
        type(app, "5551234");
        verify(findChild(app.pageStack.currentPage, "callButton").enabled);
    }

    function test_callRouteOpensDialerWithNumberWithoutDialling() {
        const app = makeApp({ route: "/call", routeParams: JSON.stringify({ number: "+353 87 123 4567" }) });
        tryCompare(app, "dialedNumber", "+353 87 123 4567");
        compare(Telephony.log.filter(e => e.indexOf("dial") === 0).length, 0);
    }

    function test_liveCallRouteFillsDialer() {
        const app = makeApp();
        app.handleRoute("/call", { number: "0871234567" });
        compare(app.dialedNumber, "0871234567");
        compare(Telephony.log.filter(e => e.indexOf("dial") === 0).length, 0);
    }

    function test_numberRowClearsTabBarOnSquareScreen() {
        const app = makeApp({}, squareAppComponent);
        dialer(app);
        type(app, "555");
        const page = app.pageStack.currentPage;
        const y = (name, dy) => {
            const item = findChild(page, name);
            return item.mapToItem(page, 0, dy ? item.height : 0).y;
        };
        tryVerify(() => y("matchLabel", true) <= y("keypad"), 2000, "number row over the keypad");
        verify(y("numberLabel") >= y("tabBar", true), "number row under the tab bar");
        verify(y("backspaceButton") >= y("tabBar", true));
        verify(y("callButton", true) <= page.height);
    }

    function test_physicalKeysDial() {
        const app = makeApp();
        dialer(app);
        keyClick(Qt.Key_5);
        keyClick(Qt.Key_7);
        compare(app.dialedNumber, "57");
        keyClick(Qt.Key_Backspace);
        compare(app.dialedNumber, "5");
    }
}
