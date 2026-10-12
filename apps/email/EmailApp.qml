pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Services
import Nemo.Configuration 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property var mail: MailService
    property QtObject draftStore: ConfigurationValue {
        key: "/apps/email/composeDraft"
        defaultValue: ""
    }
    // accounts is null when MailService couldn't reach QMailStore.
    readonly property bool serviceAvailable: mail.accounts !== null
    // rowCount() isn't notifiable; currentAccountId changes on account add/remove.
    readonly property bool hasAccount: serviceAvailable && mail.currentAccountId !== "" && mail.accounts.rowCount() > 0
    readonly property int unreadCount: hasAccount ? mail.unreadCount : 0
    property string latestSender: ""
    // A message moved from its own page waits out the inbox's remorse.
    property string pendingMoveId: ""
    property string pendingMoveKind: ""

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
        return pageStack.push(Qt.resolvedUrl("pages/MailComposePage.qml"), Object.assign({ mail: mail, draftStore: draftStore }, properties || { restoreDraft: true }));
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
        if (hasAccount)
            Qt.callLater(mail.refresh);
        updateLatest();
    }
    Component.onDestruction: commitPendingMove()

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
