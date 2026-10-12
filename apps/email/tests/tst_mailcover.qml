import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    name: "MailCover"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component { id: cover; MailCover {} }
    SignalSpy { id: newSpy; signalName: "newMessageRequested" }

    function test_unreadAndSender() {
        const c = createTemporaryObject(cover, this, { available: true, unread: 4, sender: "Ann" });
        compare(findChild(c, "unreadCount").text, "4");
        compare(findChild(c, "latestSender").text, "Ann");
        verify(findChild(c, "coverContent").visible);
        verify(!findChild(c, "coverPlaceholder").visible);
    }

    function test_placeholderWithoutAccount() {
        const c = createTemporaryObject(cover, this, { available: false });
        verify(findChild(c, "coverPlaceholder").visible);
        verify(!findChild(c, "coverContent").visible);
    }

    function test_noSenderHidesLine() {
        const c = createTemporaryObject(cover, this, { available: true, unread: 0, sender: "" });
        verify(!findChild(c, "latestSender").visible);
    }

    function test_newMessageAction() {
        const c = createTemporaryObject(cover, this, { available: true });
        newSpy.target = c;
        newSpy.clear();
        findChild(c, "newMessageAction").triggered();
        compare(newSpy.count, 1);
    }
}
