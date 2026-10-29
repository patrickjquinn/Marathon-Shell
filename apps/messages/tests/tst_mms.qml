import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: test

    readonly property real now: Date.now()

    name: "MessagesMms"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: storeStub
        QtObject {
            property var value: "{}"
        }
    }
    Component {
        id: appComponent
        MessagesApp {
            width: 540
            height: 1140
        }
    }

    function conversationWith(messages) {
        Sms.reset([
            {
                id: "a",
                contactName: "Alice",
                contactNumber: "+15551234567",
                lastMessage: "",
                lastTimestamp: now,
                unreadCount: 0
            }
        ], {
            a: messages
        });
        Telephony.hasModem = true;
        const app = createTemporaryObject(appComponent, test, {
            store: storeStub.createObject(test)
        });
        tryVerify(() => app.pageStack.currentPage && !app.pageStack.busy);
        app.openConversation(Sms.conversations[0]);
        tryVerify(() => app.pageStack.currentPage.hasOwnProperty("conversation") && !app.pageStack.busy);
        return app.pageStack.currentPage;
    }

    function test_aPictureGoesAsMms() {
        const page = conversationWith([]);
        page.attachments = [
            {
                contentType: "image/jpeg",
                filePath: "/home/u/Pictures/a.jpg",
                name: "a.jpg"
            }
        ];
        verify(findChild(page, "composerAttachment-a.jpg").visible);
        findChild(page, "messageField").text = "Look";
        verify(page.canSend);
        mouseClick(findChild(page, "sendButton"));
        compare(Sms.sentMms.length, 1);
        compare(Sms.sentMms[0].recipients, ["+15551234567"]);
        compare(Sms.sentMms[0].text, "Look");
        compare(Sms.sentMms[0].attachments[0].filePath, "/home/u/Pictures/a.jpg");
        compare(Sms.sent.length, 0);
        compare(page.attachments.length, 0);
        compare(findChild(page, "messageField").text, "");
    }

    function test_aPictureCanBeTakenOff() {
        const page = conversationWith([]);
        page.attachments = [
            {
                contentType: "image/jpeg",
                filePath: "/p/a.jpg",
                name: "a.jpg"
            },
            {
                contentType: "image/png",
                filePath: "/p/b.png",
                name: "b.png"
            }
        ];
        tryVerify(() => findChild(page, "composerAttachments").height > 0);
        const remove = findChild(findChild(page, "composerAttachment-a.jpg"), "removeAttachment");
        mouseClick(remove);
        compare(page.attachments.map(a => a.name), ["b.png"]);
    }

    function test_withoutMmsAttachSaysWhy() {
        const page = conversationWith([]);
        Sms.mmsAvailable = false;
        mouseClick(findChild(page, "attachButton"));
        const status = findChild(page, "sendStatus");
        verify(status.visible);
        verify(status.text.indexOf("MMS") >= 0);
        compare(page.app.pageStack.depth, 2);
    }

    function test_aFailedMessageSaysSoAndRetries() {
        const page = conversationWith([
            {
                id: 9,
                text: "Here",
                timestamp: now - 1000,
                isOutgoing: true,
                sender: "me",
                status: "failed",
                attachments: [
                    {
                        id: 3,
                        contentType: "image/jpeg",
                        name: "a.jpg",
                        size: 10
                    }
                ]
            }
        ]);
        const bubble = findChild(page, "bubbleStatus");
        tryVerify(() => bubble && bubble.visible);
        verify(bubble.text.indexOf("Not sent") >= 0);
        mouseClick(bubble);
        compare(Sms.sentMms.length, 1);
        compare(Sms.sentMms[0].attachments[0].filePath, "/cache/mms/3/a.jpg");
        compare(Sms.deletedMessages, [9]);
    }

    function test_aSendingMessageSaysSo() {
        const page = conversationWith([
            {
                id: 9,
                text: "Here",
                timestamp: now - 1000,
                isOutgoing: true,
                sender: "me",
                status: "sending",
                attachments: []
            }
        ]);
        tryVerify(() => findChild(page, "bubbleStatus") && findChild(page, "bubbleStatus").visible);
        verify(findChild(page, "bubbleStatus").text.indexOf("Sending") >= 0);
    }

    function test_aReceivedPictureShows() {
        const page = conversationWith([
            {
                id: 9,
                text: "",
                timestamp: now - 1000,
                isOutgoing: false,
                sender: "+15551234567",
                status: "received",
                attachments: [
                    {
                        id: 4,
                        contentType: "image/png",
                        name: "b.png",
                        size: 10
                    }
                ]
            }
        ]);
        let picture = null;
        tryVerify(() => (picture = findChild(page, "bubblePicture-b.png")) !== null && picture.visible);
        compare(String(picture.source), "file:///cache/mms/4/b.png");
        compare(Sms.opened, [4]);
    }

    // From the share sheet: a picture starts a message with it attached.
    function test_aSharedPictureStartsAnMms() {
        Sms.reset([], {});
        Telephony.hasModem = true;
        Contacts.contacts = [
            {
                name: "Bob Smith",
                phone: "+15559876543"
            }
        ];
        const app = createTemporaryObject(appComponent, test, {
            store: storeStub.createObject(test)
        });
        tryVerify(() => app.pageStack.currentPage && !app.pageStack.busy);
        app.receiveShare([
            {
                name: "beach.JPG",
                data: "",
                filePath: "/c/sailfish-share_1/beach.JPG"
            }
        ]);
        tryVerify(() => app.pageStack.currentPage.hasOwnProperty("matches") && !app.pageStack.busy);
        mouseClick(findChild(app.pageStack.currentPage, "contact-+15559876543"));
        tryVerify(() => app.pageStack.currentPage.hasOwnProperty("conversation") && !app.pageStack.busy);
        const page = app.pageStack.currentPage;
        compare(page.attachments.length, 1);
        compare(page.attachments[0].filePath, "/c/sailfish-share_1/beach.JPG");
        compare(page.attachments[0].contentType, "image/jpeg");
    }
}
