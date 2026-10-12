import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "CallLog"
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
        Navigation.reset();
        seenStub.value = 0;
        CallHistory.history = [
            { id: 7, number: "+15551234567", type: "missed", timestamp: 1700000000, duration: 0 },
            { id: 8, number: "0871234567", contactName: "Bob", type: "outgoing", timestamp: 1700000100, duration: 65 }
        ];
    }

    function openLog() {
        const app = createTemporaryObject(appComponent, testCase, { callLogSeen: seenStub });
        tryVerify(() => app.pageStack.currentPage !== null);
        app.pageStack.currentPage.tabs.moveTo(1);
        let list = null;
        tryVerify(() => (list = findChild(app.pageStack.currentPage, "callLog")) !== null && list.count === 2);
        return { app: app, list: list };
    }

    function itemAt(list, index) {
        list.currentIndex = index;
        return list.currentItem;
    }

    function menuItem(item, name) {
        item.openMenu();
        let found = null;
        tryVerify(() => (found = findChild(item.menu, name)) !== null);
        return found;
    }

    function test_listsHistoryAndMarksSeen() {
        const t = openLog();
        tryVerify(() => seenStub.value > 0);
        compare(t.app.missedCount, 0);
    }

    function test_missedCountUntilSeen() {
        const app = createTemporaryObject(appComponent, testCase, { callLogSeen: seenStub });
        compare(app.missedCount, 1);
    }

    function test_tapOpensNumberInDialer() {
        const t = openLog();
        itemAt(t.list, 1).clicked(null);
        compare(t.app.dialedNumber, "0871234567");
        tryCompare(t.app.pageStack.currentPage.tabs, "currentIndex", 0);
    }

    function test_menuCall() {
        const t = openLog();
        menuItem(itemAt(t.list, 0), "callMenuItem").clicked();
        compare(Telephony.log, ["dial:+15551234567"]);
    }

    function test_menuSendMessage() {
        Contacts.contacts = [{ id: 1, name: "Bob Byrne", phone: "087 123 4567" }];
        const t = openLog();
        menuItem(itemAt(t.list, 1), "messageMenuItem").clicked();
        compare(Navigation.launches.length, 1);
        compare(Navigation.launches[0].appId, "messages");
        compare(Navigation.launches[0].route, "conversation");
        compare(JSON.parse(Navigation.launches[0].params), { number: "0871234567", name: "Bob Byrne" });
    }

    function test_menuDeleteAfterRemorse() {
        const t = openLog();
        const item = itemAt(t.list, 0);
        menuItem(item, "deleteMenuItem").clicked();
        item.closeMenu();
        compare(CallHistory.deleted, []);
        tryCompare(CallHistory, "deleted", [7], 8000);
        tryCompare(t.list, "count", 1);
    }
}
