import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: test

    readonly property real now: Date.now()

    function sample() {
        return [
            { id: "a", contactName: "Alice", contactNumber: "+15551234567", lastMessage: "Lunch?", lastTimestamp: now - 60000, unreadCount: 2 },
            { id: "b", contactName: "", contactNumber: "+447700900123", lastMessage: "Your code is 1234", lastTimestamp: now - 3600000, unreadCount: 0 }
        ];
    }

    function makeApp(state) {
        Sms.reset(sample(), { a: [
            { id: 1, text: "Hi", timestamp: now - 120000, isOutgoing: false, sender: "+15551234567" },
            { id: 2, text: "Lunch?", timestamp: now - 60000, isOutgoing: false, sender: "+15551234567" }
        ] });
        Contacts.contacts = [{ name: "Bob Smith", phone: "+15559876543" }, { name: "Alice", phone: "+15551234567" }];
        Contacts.added = [];
        Telephony.hasModem = true;
        const store = storeStub.createObject(test, { value: state || "{}" });
        const app = createTemporaryObject(appComponent, test, { store: store });
        tryVerify(() => app.pageStack.currentPage && !app.pageStack.busy && findChild(app.pageStack.currentPage, "conversationList"));
        return app;
    }

    function page(app) {
        return app.pageStack.currentPage;
    }

    function waitForPage(app, prop) {
        tryVerify(() => page(app).hasOwnProperty(prop) && !app.pageStack.busy, 5000);
        return page(app);
    }

    name: "MessagesApp"
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

    function test_storeIsAConfigurationValue() {
        const app = createTemporaryObject(appComponent, test);
        compare(app.store.key, "/apps/messages/state");
    }

    function test_listShowsConversations() {
        const app = makeApp();
        const view = findChild(page(app), "conversationList");
        compare(view.count, 2);
        verify(findChild(view, "conversation-a"));
    }

    function test_pinnedFirstAndArchivedHidden() {
        const app = makeApp(JSON.stringify({ pinned: ["b"], archived: [], drafts: {} }));
        compare(page(app).visibleConversations[0].id, "b");
        app.setArchived("b", true);
        compare(page(app).visibleConversations.map(c => c.id), ["a"]);
        compare(JSON.parse(app.store.value).archived, ["b"]);
    }

    function test_incomingMessageUnarchives() {
        const app = makeApp(JSON.stringify({ archived: ["a"] }));
        Sms.messageReceived("5551234567", "hey", now);
        compare(app.archivedIds, []);
    }

    function test_openConversationShowsMessagesAndMarksRead() {
        const app = makeApp();
        mouseClick(findChild(page(app), "conversation-a"));
        const conv = waitForPage(app, "conversation");
        compare(conv.conversation.id, "a");
        compare(findChild(conv, "messageList").count, 2);
        compare(Sms.read, ["a"]);
    }

    function test_sendClearsFieldOnConfirmation() {
        const app = makeApp();
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        const field = findChild(conv, "messageField");
        const button = findChild(conv, "sendButton");
        verify(!button.enabled);
        field.text = "On my way";
        verify(button.enabled);
        mouseClick(button);
        compare(Sms.sent, [{ recipient: "+15551234567", text: "On my way" }]);
        compare(findChild(conv, "sendStatus").text, "Sending…");
        verify(!button.enabled);
        Sms.messageSent("+15551234567", now);
        compare(field.text, "");
        verify(!findChild(conv, "sendStatus").visible);
    }

    function test_enterKeySends() {
        const app = makeApp();
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        const field = findChild(conv, "messageField");
        field.forceActiveFocus();
        keyClick(Qt.Key_O);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_Return);
        compare(Sms.sent, [{ recipient: "+15551234567", text: "ok" }]);
    }

    function test_sendFailureKeepsText() {
        const app = makeApp();
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        const field = findChild(conv, "messageField");
        field.text = "Hello";
        conv.send();
        Sms.sendFailed("+15551234567", "No modem");
        compare(field.text, "Hello");
        verify(/No mobile network/.test(findChild(conv, "sendStatus").text));
        verify(findChild(conv, "sendButton").enabled);
    }

    function test_draftIsKeptPerConversation() {
        const app = makeApp();
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        findChild(conv, "messageField").text = "half a thought";
        compare(app.drafts.a, "half a thought");
        app.save();
        compare(JSON.parse(app.store.value).drafts.a, "half a thought");
        app.pageStack.pop();
        tryVerify(() => page(app).hasOwnProperty("archive") && !app.pageStack.busy);
        app.openConversation(sample()[0]);
        compare(findChild(waitForPage(app, "conversation"), "messageField").text, "half a thought");
    }

    function test_routeOpensNewConversation() {
        Sms.reset(sample(), {});
        Contacts.contacts = [{ name: "Bob Smith", phone: "+15559876543" }];
        const store = storeStub.createObject(test, { value: "{}" });
        const app = createTemporaryObject(appComponent, test, { store: store, route: "conversation", routeParams: JSON.stringify({ number: "+1 555 987 6543" }) });
        const conv = waitForPage(app, "conversation");
        compare(conv.conversation.contactNumber, "+1 555 987 6543");
        compare(conv.contactName, "Bob Smith");
        compare(app.pageStack.depth, 2);
    }

    function test_routeOpensExistingThread() {
        Sms.reset(sample(), {});
        const store = storeStub.createObject(test, { value: "{}" });
        const app = createTemporaryObject(appComponent, test, { store: store, route: "conversation", routeParams: JSON.stringify({ number: "5551234567" }) });
        compare(waitForPage(app, "conversation").conversation.id, "a");
    }

    function test_noModemBlocksSendButKeepsTyping() {
        const app = makeApp();
        Telephony.hasModem = false;
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        verify(findChild(conv, "noModem").visible);
        const field = findChild(conv, "messageField");
        field.text = "later";
        verify(!findChild(conv, "sendButton").enabled);
        conv.send();
        compare(Sms.sent, []);
        compare(app.drafts.a, "later");
        Telephony.hasModem = true;
        verify(!findChild(conv, "noModem").visible);
        verify(findChild(conv, "sendButton").enabled);
    }

    function test_callFromPulley() {
        const app = makeApp();
        Navigation.launches = [];
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        compare(conv.contactName, "Alice");
        findChild(conv, "callItem").clicked();
        compare(Navigation.launches, [{ appId: "phone", route: "/call", params: JSON.stringify({ number: "+15551234567" }) }]);
    }

    function test_addUnknownNumberToContacts() {
        const app = makeApp();
        app.openConversation(sample()[1]);
        const conv = waitForPage(app, "conversation");
        compare(conv.contactName, "");
        findChild(conv, "addContactItem").clicked();
        tryVerify(() => page(app).hasOwnProperty("number") && !app.pageStack.busy);
        const dialog = page(app);
        verify(!dialog.canAccept);
        findChild(dialog, "nameField").text = "Dana";
        dialog.accept();
        tryVerify(() => page(app) === conv && !app.pageStack.busy);
        compare(Contacts.added, [{ name: "Dana", phone: "+447700900123" }]);
        compare(conv.contactName, "Dana");
    }

    function test_bubblesHaveNoFillAndCanBeCopied() {
        const app = makeApp();
        Sms.messages = { a: [
            { id: 1, text: "Hi", timestamp: now - 120000, isOutgoing: false, sender: "+15551234567" },
            { id: 2, text: "Hello", timestamp: now - 60000, isOutgoing: true, sender: "" }
        ] };
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        const view = findChild(conv, "messageList");
        let incoming = null;
        let outgoing = null;
        tryVerify(() => (incoming = view.itemAtIndex(0)) && (outgoing = view.itemAtIndex(1)));
        compare(findChild(incoming, "messageText").color, Theme.highlightColor);
        compare(findChild(outgoing, "messageText").color, Theme.primaryColor);
        verify(findChild(outgoing, "messageText").x > findChild(incoming, "messageText").x);
        Clipboard.text = "";
        outgoing.openMenu();
        tryVerify(() => outgoing.menuOpen && outgoing._menuItem._expanded && !outgoing._menuItem._displayHeightAnimating);
        const copy = findChild(outgoing._menuItem, "copyItem");
        mouseClick(copy);
        tryCompare(Clipboard, "text", "Hello");
    }

    function test_deleteMessageWithRemorse() {
        const app = makeApp();
        app.openConversation(sample()[0]);
        const conv = waitForPage(app, "conversation");
        const view = findChild(conv, "messageList");
        let first = null;
        tryVerify(() => (first = view.itemAtIndex(0)));
        first.openMenu();
        tryVerify(() => first.menuOpen && first._menuItem._expanded && !first._menuItem._displayHeightAnimating);
        const del = findChild(first._menuItem, "deleteItem");
        tryVerify(() => del.visible && del.height > 0);
        mouseClick(del);
        compare(Sms.deletedMessages, []);
        tryCompare(Sms, "deletedMessages", [1], 8000);
        tryCompare(view, "count", 1);
        compare(conv.messages[0].text, "Lunch?");
    }

    function test_newMessageWithContact() {
        const app = makeApp();
        app.newMessage();
        const picker = waitForPage(app, "matches");
        compare(picker.matches.length, 2);
        mouseClick(findChild(picker, "contact-+15559876543"));
        const conv = waitForPage(app, "conversation");
        compare(conv.conversation.contactName, "Bob Smith");
        compare(conv.conversation.id, "conv_+15559876543");
        compare(app.pageStack.depth, 2);
    }

    function test_newMessageReusesExistingThread() {
        const app = makeApp();
        app.newMessage();
        const picker = waitForPage(app, "matches");
        const field = findChild(picker, "recipientField");
        field.text = "555 123 4567";
        verify(picker.isNumber);
        picker.startWithTyped();
        compare(waitForPage(app, "conversation").conversation.id, "a");
    }

    function test_newMessageTypesIntoRecipient() {
        const app = makeApp();
        app.newMessage();
        const picker = waitForPage(app, "matches");
        const field = findChild(picker, "recipientField");
        tryVerify(() => field._editor.activeFocus);
        keyClick(Qt.Key_B);
        compare(field.text, "b");
        compare(picker.matches.map(c => c.name), ["Bob Smith"]);
        tryVerify(() => !findChild(picker, "contact-+15551234567"));
    }

    function test_searchFiltersList() {
        const app = makeApp(JSON.stringify({ pinned: ["b"] }));
        const list = page(app);
        list.searching = true;
        const field = findChild(list, "searchField");
        tryVerify(() => field._editor.activeFocus);
        keyClick(Qt.Key_C);
        keyClick(Qt.Key_O);
        Sms.conversations = Sms.conversations.concat([{ id: "n", contactName: "New", contactNumber: "1", lastMessage: "promo code", lastTimestamp: now, unreadCount: 1 }]);
        keyClick(Qt.Key_D);
        compare(field.text, "cod");
        compare(list.visibleConversations.map(c => c.id), ["b", "n"]);
        list.searching = false;
        compare(field.text, "");
        compare(findChild(list, "conversationList").count, 3);
    }

    function test_newMessageSearchesContacts() {
        const app = makeApp();
        app.newMessage();
        const picker = waitForPage(app, "matches");
        findChild(picker, "recipientField").text = "bob";
        compare(picker.matches.map(c => c.name), ["Bob Smith"]);
        tryVerify(() => !findChild(picker, "contact-+15551234567"));
        verify(!picker.isNumber);
    }

    function test_deleteWithRemorse() {
        const app = makeApp(JSON.stringify({ pinned: ["a"], drafts: { a: "x" } }));
        const item = findChild(page(app), "conversation-a");
        item.openMenu();
        tryVerify(() => item.menuOpen && item._menuItem._expanded && !item._menuItem._displayHeightAnimating);
        const del = findChild(item._menuItem, "deleteItem");
        tryVerify(() => del.visible && del.height > 0);
        mouseClick(del);
        compare(Sms.deleted, []);
        tryCompare(Sms, "deleted", ["a"], 8000);
        compare(app.pinnedIds, []);
        compare(app.drafts.a, undefined);
        compare(findChild(page(app), "conversationList").count, 1);
    }
}
