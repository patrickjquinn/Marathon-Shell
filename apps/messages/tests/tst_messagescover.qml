import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    name: "MessagesCover"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: cover
        MessagesCover {}
    }
    SignalSpy {
        id: newSpy
        signalName: "newMessageRequested"
    }

    function test_unreadAndLatestSender() {
        const c = createTemporaryObject(cover, this, {
            conversations: [
                {
                    id: "a",
                    contactName: "Alice",
                    contactNumber: "1",
                    lastMessage: "hi",
                    unreadCount: 2
                },
                {
                    id: "b",
                    contactName: "",
                    contactNumber: "+15551234567",
                    lastMessage: "yo",
                    unreadCount: 1
                }
            ]
        });
        compare(c.unread, 3);
        compare(findChild(c, "coverUnread").value, "3");
        compare(findChild(c, "coverConversations").count, 1);
        compare(findChild(c, "coverSender").text, "Alice");
        verify(!findChild(c, "coverPlaceholder").visible);
    }

    function test_noUnread() {
        const c = createTemporaryObject(cover, this, {
            conversations: [
                {
                    id: "b",
                    contactName: "",
                    contactNumber: "+15551234567",
                    lastMessage: "yo",
                    unreadCount: 0
                }
            ]
        });
        verify(!findChild(c, "coverUnread").visible);
        compare(findChild(c, "coverSender").text, "+1 555 123 4567");
    }

    function test_placeholderWhenEmpty() {
        const c = createTemporaryObject(cover, this, {
            conversations: []
        });
        verify(findChild(c, "coverPlaceholder").visible);
        compare(findChild(c, "coverPlaceholder").icon.source.toString(), "image://theme/icon-l-message");
    }

    function test_newMessageAction() {
        const c = createTemporaryObject(cover, this, {
            conversations: []
        });
        newSpy.target = c;
        newSpy.clear();
        findChild(c, "newMessageAction").triggered();
        compare(newSpy.count, 1);
    }
}
