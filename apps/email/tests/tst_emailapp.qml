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

    // A pull-down from the page's top opens its pulley menu.
    function pulleyIn(item) {
        if (!item)
            return null;
        if (item._isPullDownMenu === true && item.visible)
            return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const found = pulleyIn(children[i]);
            if (found)
                return found;
        }
        return null;
    }

    function pullDown(item) {
        const menu = pulleyIn(item);
        verify(menu, "a pull-down menu");
        const x = item.width / 2;
        mousePress(item, x, 300);
        for (let y = 320; y <= 780; y += 40)
            mouseMove(item, x, y, 16);
        verify(menu.active, "pulley open");
        mouseRelease(item, x, 780);
        return menu;
    }

    function test_inboxPulleyOpens() {
        const app = makeApp();
        pullDown(inbox(app));
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
        verify(findChild(add, "provider-imap"));
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
        verify(compose.draftKey.indexOf("new-") === 0);
    }

    function test_pulleyBusyWhileSyncing() {
        withMessages();
        const app = makeApp();
        const pulley = findChild(inbox(app), "pulley");
        const sync = findChild(inbox(app), "syncItem");
        verify(!pulley.busy);
        MailService.syncState = "syncing";
        verify(pulley.busy);
        compare(sync.text, "Stop");
        sync.clicked();
        compare(MailService.called("cancelSync").length, 1);
        MailService.syncState = "idle";
        verify(!pulley.busy);
        compare(sync.text, "Sync");
    }

    function test_syncTimesOut() {
        MailService.setAccount("Work");
        MailService.syncState = "connecting";
        const app = makeApp();
        const page = inbox(app);
        verify(findChild(page, "busy").running);
        verify(findChild(page, "syncTimeout").running);
        findChild(page, "syncTimeout").triggered();
        verify(!findChild(page, "busy").running);
        compare(findChild(page, "placeholder").text, "Couldn't load your mail");
        findChild(page, "syncItem").clicked();
        verify(findChild(page, "busy").running);
    }

    function test_outboxInHeader() {
        withMessages();
        MailService.outboxCount = 2;
        const app = makeApp();
        compare(view(app).headerItem.children[0].description, "Work · 1 unread · 2 in Outbox");
    }

    function test_sendResultNotices() {
        withMessages();
        const app = makeApp();
        Notices._queue = [];
        Notices._dismissCurrent();
        MailService.sendFailed("offline");
        compare(Notices._current.text, "Not sent — you're offline. It'll stay in Outbox; pull down in Inbox to retry.");
        Notices._dismissCurrent();
        MailService.sendSucceeded();
        compare(Notices._current.text, "Sent");
        Notices._dismissCurrent();
    }

    function test_continueDraft() {
        withMessages();
        const app = makeApp();
        verify(!findChild(inbox(app), "draftItem").visible);
        app.draftStore.value = JSON.stringify({ "reply-2": { to: "bob@x.org", subject: "Re: Report", body: "ok", savedAt: 5 } });
        const item = findChild(inbox(app), "draftItem");
        compare(item.text, "Continue draft");
        item.clicked();
        const compose = pushed(app, 2);
        compare(compose.draftKey, "reply-2");
        compare(findChild(compose, "toField").text, "bob@x.org");
    }

    function test_severalDraftsOpenList() {
        withMessages();
        const app = makeApp();
        app.draftStore.value = JSON.stringify({ "new-1": { subject: "One", savedAt: 1 }, "new-2": { subject: "Two", savedAt: 2 } });
        compare(findChild(inbox(app), "draftItem").text, "Drafts");
        app.continueDraft();
        const drafts = pushed(app, 2);
        compare(findChild(drafts, "draftView").count, 2);
        mouseClick(findChild(drafts, "draft-new-1"));
        compare(pushed(app, 3).draftKey, "new-1");
    }

    function test_legacyDraftMigrates() {
        withMessages();
        const store = createTemporaryObject(valueStub, testCase, { value: "{}" });
        const legacy = createTemporaryObject(valueStub, testCase, { value: JSON.stringify({ to: "a@b.co", cc: "", subject: "Old", body: "" }) });
        const app = createTemporaryObject(appComponent, testCase, { draftStore: store, legacyDraft: legacy });
        compare(app.drafts.length, 1);
        compare(app.drafts[0].subject, "Old");
        compare(legacy.value, "");
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

    function test_markUnreadFromMessagePage() {
        withMessages();
        const app = makeApp();
        app.openMessage("2");
        const msg = pushed(app, 2);
        findChild(msg, "unreadItem").clicked();
        pushed(app, 1);
        const calls = MailService.called("markAsRead");
        compare(calls[calls.length - 1].args, ["2", false]);
    }

    function test_searchFiltersInbox() {
        withMessages();
        const app = makeApp();
        const page = inbox(app);
        findChild(page, "searchItem").clicked();
        verify(page.searching);
        findChild(page, "searchField").text = "bob";
        tryCompare(view(app), "count", 1);
        tryVerify(() => view(app).itemAtIndex(0) && view(app).itemAtIndex(0).messageId === "2");
        findChild(page, "searchField").text = "nobody";
        tryCompare(view(app), "count", 0);
        const p = findChild(page, "placeholder");
        verify(p.enabled);
        compare(p.text, "No matching messages");
        findChild(page, "searchItem").clicked();
        verify(!page.searching);
        tryCompare(view(app), "count", 3);
    }

    function test_searchKeepsNewMail() {
        withMessages();
        const app = makeApp();
        const page = inbox(app);
        page.searching = true;
        findChild(page, "searchField").text = "lunch";
        tryCompare(view(app), "count", 1);
        MailService.addMessage(9, "Dee", "Lunch again", true);
        tryCompare(view(app), "count", 2);
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
        compare(app.latestSubject, MailService.messageModel.get(0).subject);
        MailService.messageModel.remove(0);
        tryCompare(app, "latestSender", "Bob");
        MailService.messageModel.setProperty(0, "from", "Bea");
        tryCompare(app, "latestSender", "Bea");
    }

    function accountList() {
        return [
            { id: "1", name: "Work", address: "me@work.org", unread: 1, folders: [
                { id: "10", name: "Inbox", kind: "inbox", unread: 1, count: 3 },
                { id: "11", name: "Sent", kind: "sent", unread: 0, count: 4 },
                { id: "outbox", name: "Outbox", kind: "outbox", unread: 0, count: 1 },
                { id: "12", name: "Trash", kind: "trash", unread: 0, count: 0 }
            ] },
            { id: "2", name: "Home", address: "me@home.org", unread: 0, folders: [
                { id: "20", name: "Inbox", kind: "inbox", unread: 0, count: 0 }
            ] }
        ];
    }

    function test_accountsPageListsFolders() {
        withMessages();
        MailService.accountList = accountList();
        const app = makeApp();
        verify(!findChild(inbox(app), "accountsItem").visible);
        tryVerify(() => app.pageStack.nextPage(inbox(app)) !== null);
        app.pageStack.navigateForward();
        const accounts = pushed(app, 2);
        compare(accounts.objectName, "accountsPage");
        compare(findChild(accounts, "accounts").count, 2);
        compare(MailService.called("refreshFolders").map(c => c.args[0]), ["1", "2"]);
        verify(findChild(accounts, "folder-Work-inbox").current);
        verify(!findChild(accounts, "folder-Work-inbox").highlighted);
        compare(findChild(findChild(accounts, "folder-Work-inbox"), "folderName").color, Theme.highlightColor);
        compare(findChild(findChild(accounts, "folder-Work-trash"), "folderName").color, Theme.primaryColor);
        verify(findChild(accounts, "folder-Work-outbox"));
        verify(findChild(accounts, "folder-Home-inbox").enabled);
    }

    function test_openTrashFolder() {
        withMessages();
        MailService.accountList = accountList();
        const app = makeApp();
        tryVerify(() => app.pageStack.nextPage(inbox(app)) !== null);
        app.pageStack.navigateForward();
        const accounts = pushed(app, 2);
        const trash = findChild(accounts, "folder-Work-trash");
        tryVerify(() => trash.mapToItem(accounts, 0, 0).y > 0);
        mouseClick(trash);
        pushed(app, 1);
        compare(MailService.currentFolderId, "12");
        compare(app.folderKind, "trash");
        MailService.messageModel.clear();
        compare(findChild(inbox(app), "placeholder").text, "No messages");
    }

    function test_switchAccount() {
        withMessages();
        MailService.accountList = accountList();
        const app = makeApp();
        app.pageStack.push(Qt.resolvedUrl("../pages/AccountsPage.qml"), { app: app });
        const accounts = pushed(app, 2);
        tryVerify(() => MailService.called("refresh").length === 1);
        findChild(accounts, "folder-Home-inbox").clicked(null);
        pushed(app, 1);
        compare(MailService.currentAccountId, "2");
        compare(MailService.currentFolderId, "20");
        compare(MailService.called("refresh").length, 2);
    }

    function test_coverCompose() {
        withMessages();
        const app = makeApp();
        app.compose();
        verify(pushed(app, 2).draftKey.indexOf("new-") === 0);
    }
}
