pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Services
import Nemo.Configuration 1.0
import "MailLogic.js" as Logic
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property var mail: MailService
    property QtObject draftStore: ConfigurationValue {
        key: "/apps/email/drafts"
        defaultValue: "{}"
    }
    property QtObject legacyDraft: ConfigurationValue {
        key: "/apps/email/composeDraft"
        defaultValue: ""
    }
    readonly property var drafts: Logic.draftList(Logic.parseDrafts(draftStore ? draftStore.value : ""))
    // accounts is null when MailService couldn't reach QMailStore.
    readonly property bool serviceAvailable: mail.accounts !== null
    // rowCount() isn't notifiable; currentAccountId changes on account add/remove.
    readonly property bool hasAccount: serviceAvailable && mail.currentAccountId !== "" && mail.accounts.rowCount() > 0
    readonly property int unreadCount: hasAccount ? mail.unreadCount : 0
    property string latestSender: ""
    // A message moved from its own page waits out the inbox's remorse.
    property string pendingMoveId: ""
    property string pendingMoveKind: ""
    // Kind of the open folder (inbox, sent, outbox…) for its empty state.
    property string folderKind: "inbox"

    function commitPendingMove() {
        if (pendingMoveId === "")
            return;
        const id = pendingMoveId;
        const kind = pendingMoveKind;
        pendingMoveId = "";
        pendingMoveKind = "";
        move(id, kind);
    }

    function cancelPendingMove() {
        pendingMoveId = "";
        pendingMoveKind = "";
    }

    function move(id, kind) {
        if (kind === "archive" ? mail.moveToArchive(id) : mail.moveToTrash(id))
            return true;
        Notices.show(kind === "archive" ? qsTr("No Archive folder on this account") : qsTr("Couldn't delete the message. Try again."));
        return false;
    }

    function requestMove(id, kind) {
        commitPendingMove();
        pendingMoveId = id;
        pendingMoveKind = kind;
        const inbox = showInbox();
        inbox.remorseMove(kind);
    }

    function showInbox() {
        const inbox = pageStack.find(p => p.objectName === "inboxPage");
        if (pageStack.currentPage !== inbox)
            pageStack.pop(inbox);
        return inbox;
    }

    function compose(properties) {
        return pageStack.push(Qt.resolvedUrl("pages/MailComposePage.qml"), Object.assign({ mail: mail, draftStore: draftStore, draftKey: "new-" + Date.now() }, properties || {}));
    }

    function continueDraft() {
        if (drafts.length === 1)
            return compose({ draftKey: drafts[0].key });
        return pageStack.push(Qt.resolvedUrl("pages/DraftsPage.qml"), { app: app });
    }

    function deleteDraft(key) {
        draftStore.value = Logic.withDraft(draftStore.value, key, { to: "", cc: "", bcc: "", subject: "", body: "" }, 0);
    }

    function openFolder(accountId, folderId, kind) {
        mail.currentAccountId = accountId;
        mail.currentFolderId = folderId;
        folderKind = kind;
        showInbox();
        if (kind !== "outbox")
            mail.refresh();
    }

    function openMessage(id) {
        mail.markAsRead(id, true);
        return pageStack.push(Qt.resolvedUrl("pages/MailMessagePage.qml"), { app: app, messageId: id });
    }

    function updateLatest() {
        latestSender = hasAccount && latest.items.count > 0 ? String(latest.items.get(0).model.from || "") : "";
    }

    appId: "email"
    onApplicationActiveChanged: {
        const page = pageStack.currentPage;
        if (!applicationActive && page && page.edited)
            page.persistDraft();
    }
    onHasAccountChanged: {
        if (hasAccount)
            Qt.callLater(mail.refresh);
        updateLatest();
    }
    Component.onCompleted: {
        const legacy = Logic.parseDrafts(legacyDraft.value);
        if (legacy.to !== undefined) {
            draftStore.value = Logic.withDraft(draftStore.value, "new-0", Object.assign({ to: "", cc: "", bcc: "", subject: "", body: "" }, legacy), 0);
            legacyDraft.value = "";
        }
        if (hasAccount)
            Qt.callLater(mail.refresh);
        updateLatest();
    }
    Component.onDestruction: commitPendingMove()

    Connections {
        target: app.mail
        ignoreUnknownSignals: true
        function onSendSucceeded() {
            Notices.show(qsTr("Sent"));
        }
        function onSendFailed(reason) {
            Notices.show(Logic.sendFailureText(reason));
        }
        function onCurrentFolderChanged() {
            app.folderKind = "inbox";
        }
    }

    DelegateModel {
        id: latest

        model: app.hasAccount ? app.mail.messages : null
        onModelChanged: Qt.callLater(app.updateLatest)
    }
    Connections {
        target: app.hasAccount ? app.mail.messages : null
        ignoreUnknownSignals: true
        function onDataChanged() {
            Qt.callLater(app.updateLatest);
        }
        function onModelReset() {
            Qt.callLater(app.updateLatest);
        }
        function onRowsInserted() {
            Qt.callLater(app.updateLatest);
        }
        function onRowsRemoved() {
            Qt.callLater(app.updateLatest);
        }
        function onLayoutChanged() {
            Qt.callLater(app.updateLatest);
        }
    }

    cover: Component {
        MailCover {
            available: app.hasAccount
            unread: app.unreadCount
            sender: app.latestSender
            onNewMessageRequested: {
                app.activate();
                app.compose();
            }
        }
    }

    initialPage: Component {
        InboxPage {
            app: app
        }
    }
}
