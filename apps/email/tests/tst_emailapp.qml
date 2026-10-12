import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Services
import ".."

TestCase {
    id: testCase
    name: "EmailApp"
    when: windowShown
    visible: true
    width: 540; height: 1140

    Component {
        id: valueStub
        QtObject {
            property var value: ""
        }
    }
    Component {
        id: appComponent
        EmailApp { width: 540; height: 1140 }
    }

    function init() {
        MailService.reset();
    }

    function makeApp(props) {
        const store = createTemporaryObject(valueStub, testCase);
        const app = createTemporaryObject(appComponent, testCase, Object.assign({ draftStore: store }, props || {}));
        tryVerify(() => app.pageStack.currentPage !== null && !app.pageStack.busy);
        return app;
    }

    function withMessages() {
        MailService.setAccount("Work");
        MailService.addMessage(3, "Ann", "Lunch", true, { hasAttachment: true });
        MailService.addMessage(2, "Bob", "Report", false);
        MailService.addMessage(1, "Cy", "Old news", false);
    }

    function inbox(app) {
        return app.pageStack.find(p => p.objectName === "inboxPage");
    }

    function view(app) {
        return findChild(inbox(app), "messageView");
    }

    function delegateAt(v, index) {
        let item = null;
        tryVerify(() => (item = v.itemAtIndex(index)) !== null);
        return item;
    }

    function tapMenuItem(menu, name) {
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        mouseClick(findChild(menu, name));
    }

    function pushed(app, depth) {
        tryCompare(app.pageStack, "depth", depth);
        tryVerify(() => !app.pageStack.busy);
        return app.pageStack.currentPage;
    }

    function test_serviceUnavailable() {
        MailService.accounts = null;
        const app = makeApp();
        verify(!app.serviceAvailable);
        const p = findChild(inbox(app), "placeholder");
        verify(p.enabled);
        compare(p.text, "Mail isn't available");
    }

    function test_noAccount() {
        const app = makeApp();
        verify(app.serviceAvailable && !app.hasAccount);
        compare(findChild(inbox(app), "placeholder").text, "No mail accounts");
        compare(findChild(inbox(app), "accountsItem").text, "Add account");
        verify(!findChild(inbox(app), "newMessageItem").visible);
        compare(MailService.called("refresh").length, 0);
    }

    function test_addAccountFromPulley() {
        const app = makeApp();
        findChild(inbox(app), "accountsItem").clicked();
        const add = pushed(app, 2);
        verify(findChild(add, "provider-gmail"));
    }

    function test_loading() {
        MailService.setAccount("Work");
        MailService.syncState = "syncing";
        const app = makeApp();
        verify(findChild(inbox(app), "busy").running);
        verify(!findChild(inbox(app), "placeholder").enabled);
    }

    function test_inboxZero() {
        MailService.setAccount("Work");
        const app = makeApp();
        tryVerify(() => MailService.called("refresh").length === 1);
        wait(50);
        compare(MailService.called("refresh").length, 1);
        const p = findChild(inbox(app), "placeholder");
        verify(p.enabled);
        compare(p.text, "Inbox zero");
    }

    function test_loadError() {
        MailService.setAccount("Work");
        MailService.syncState = "error";
        const app = makeApp();
        compare(findChild(inbox(app), "placeholder").text, "Couldn't load your mail");
    }

    function test_listsMessages() {
        withMessages();
        const app = makeApp();
        compare(view(app).count, 3);
        verify(!findChild(inbox(app), "placeholder").enabled);
        const first = delegateAt(view(app), 0);
        verify(first.unread);
        verify(findChild(first, "unreadMarker").visible);
        verify(!findChild(delegateAt(view(app), 1), "unreadMarker").visible);
        compare(view(app).headerItem.children[0].description, "Work · 1 unread");
    }

    function test_syncErrorWithMessages() {
        withMessages();
        MailService.syncState = "error";
        const app = makeApp();
        verify(findChild(view(app).headerItem, "syncError").visible);
    }

    function test_pulleySyncAndNew() {
        withMessages();
        const app = makeApp();
        tryVerify(() => MailService.called("refresh").length === 1);
        findChild(inbox(app), "syncItem").clicked();
        compare(MailService.called("refresh").length, 2);
        findChild(inbox(app), "newMessageItem").clicked();
        const compose = pushed(app, 2);
        verify(compose.restoreDraft);
    }

    function test_tapOpensAndMarksRead() {
        withMessages();
        MailService.bodies = { "3": { subject: "Lunch", from: "Ann", bodyPlain: "Noon?" } };
        const app = makeApp();
        mouseClick(delegateAt(view(app), 0));
        const msg = pushed(app, 2);
        compare(msg.messageId, "3");
        compare(MailService.called("markAsRead")[0].args, ["3", true]);
        compare(app.unreadCount, 0);
    }

    function test_contextMarkUnread() {
        withMessages();
        const app = makeApp();
        const menu = delegateAt(view(app), 1).openMenu();
        tapMenuItem(menu, "readItem");
        compare(MailService.called("markAsRead")[0].args, ["2", false]);
        tryVerify(() => delegateAt(view(app), 1).unread);
    }

    function test_contextRemorseDelete() {
        withMessages();
        const app = makeApp();
        const menu = delegateAt(view(app), 0).openMenu();
        tapMenuItem(menu, "deleteItem");
        compare(MailService.called("moveToTrash").length, 0);
        tryVerify(() => MailService.called("moveToTrash").length === 1, 10000);
        compare(MailService.called("moveToTrash")[0].args, ["3"]);
    }

    function test_contextArchive() {
        withMessages();
        const app = makeApp();
        const menu = delegateAt(view(app), 2).openMenu();
        tapMenuItem(menu, "archiveItem");
        tryVerify(() => MailService.called("moveToArchive").length === 1, 10000);
        compare(MailService.called("moveToArchive")[0].args, ["1"]);
    }

    function test_deleteFromMessagePage() {
        withMessages();
        const app = makeApp();
        app.openMessage("2");
        const msg = pushed(app, 2);
        findChild(msg, "deleteItem").clicked();
        pushed(app, 1);
        compare(app.pendingMoveId, "2");
        verify(delegateAt(view(app), 1).hidden);
        verify(findChild(inbox(app), "remorse").active);
        tryVerify(() => MailService.called("moveToTrash").length === 1, 10000);
        compare(app.pendingMoveId, "");
    }

    function test_cancelMoveFromMessagePage() {
        withMessages();
        const app = makeApp();
        app.openMessage("2");
        findChild(pushed(app, 2), "archiveItem").clicked();
        pushed(app, 1);
        findChild(inbox(app), "remorse").cancel();
        compare(app.pendingMoveId, "");
        wait(100);
        compare(MailService.called("moveToArchive").length, 0);
        verify(!delegateAt(view(app), 1).hidden);
    }

    function test_failedMoveKeepsPage() {
        withMessages();
        MailService.fail = true;
        const app = makeApp();
        verify(!app.move("3", "trash"));
        compare(view(app).count, 3);
    }

    function test_latestSender() {
        withMessages();
        const app = makeApp();
        compare(app.latestSender, "Ann");
        MailService.messageModel.remove(0);
        tryCompare(app, "latestSender", "Bob");
        MailService.messageModel.setProperty(0, "from", "Bea");
        tryCompare(app, "latestSender", "Bea");
    }

    function test_accountsPage() {
        withMessages();
        MailService.accountModel.append({ display: "Home" });
        const app = makeApp();
        findChild(inbox(app), "accountsItem").clicked();
        const accounts = pushed(app, 2);
        compare(findChild(accounts, "accounts").count, 2);
        const work = findChild(accounts, "folder-Work");
        verify(work.enabled);
        verify(!findChild(accounts, "folder-Home").enabled);
        tryVerify(() => work.mapToItem(accounts, 0, 0).y > 0);
        mouseClick(work);
        pushed(app, 1);
    }

    function test_coverCompose() {
        withMessages();
        const app = makeApp();
        app.compose();
        verify(pushed(app, 2).restoreDraft);
    }
}
