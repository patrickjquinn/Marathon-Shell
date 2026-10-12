pragma Singleton
import QtQuick

QtObject {
    id: svc

    property ListModel accountModel: ListModel {}
    property ListModel messageModel: ListModel {}
    property var accounts: accountModel
    property var messages: messageModel
    property string currentAccountId: ""
    property string currentAccountName: ""
    property string currentFolderId: ""
    property string currentFolderName: ""
    property int unreadCount: 0
    property string syncState: "idle"
    property string lastError: ""
    property bool fail: false
    property var bodies: ({})
    property var calls: []

    signal oauthAuthUrlReady(string url)
    signal oauthLoginSucceeded(string accountId)
    signal oauthLoginFailed(string code, string message)

    function log(name, args) {
        calls = calls.concat([{ name: name, args: args }]);
    }

    function called(name) {
        return calls.filter(c => c.name === name);
    }

    function reset() {
        accountModel.clear();
        messageModel.clear();
        accounts = accountModel;
        messages = messageModel;
        currentAccountId = "";
        currentAccountName = "";
        currentFolderId = "";
        currentFolderName = "";
        unreadCount = 0;
        syncState = "idle";
        fail = false;
        bodies = {};
        calls = [];
    }

    function setAccount(name) {
        accountModel.append({ display: name });
        currentAccountName = name;
        currentFolderId = "10";
        currentFolderName = "Inbox";
        currentAccountId = "1";
    }

    function addMessage(id, from, subject, unread, extra) {
        messageModel.append(Object.assign({ messageId: id, from: from, subject: subject, snippet: "Preview of " + subject, timestamp: "09:30", unread: unread, hasAttachment: false, tint: "" }, extra || {}));
        recount();
    }

    function recount() {
        let n = 0;
        for (let i = 0; i < messageModel.count; ++i)
            if (messageModel.get(i).unread)
                ++n;
        unreadCount = n;
    }

    function rowOf(id) {
        for (let i = 0; i < messageModel.count; ++i)
            if (String(messageModel.get(i).messageId) === String(id))
                return i;
        return -1;
    }

    function refresh() {
        log("refresh", []);
        return currentAccountId !== "";
    }

    function markAsRead(id, read) {
        log("markAsRead", [id, read]);
        const row = rowOf(id);
        if (row >= 0)
            messageModel.setProperty(row, "unread", !read);
        recount();
        return row >= 0;
    }

    function move(name, id) {
        log(name, [id]);
        if (fail)
            return false;
        const row = rowOf(id);
        if (row >= 0)
            messageModel.remove(row);
        recount();
        return row >= 0;
    }

    function moveToTrash(id) {
        return move("moveToTrash", id);
    }

    function moveToArchive(id) {
        return move("moveToArchive", id);
    }

    function send(to, cc, subject, body, attachments) {
        log("send", [to, cc, subject, body, attachments]);
        return !fail;
    }

    function openMessage(id) {
        return bodies[id] || {};
    }

    function addImapAccount(name, email, imapHost, imapPort, imapEnc, smtpHost, smtpPort, smtpEnc, username, password) {
        log("addImapAccount", [name, email, imapHost, imapPort, imapEnc, smtpHost, smtpPort, smtpEnc, username, password]);
        if (fail)
            return "";
        setAccount(name);
        return "1";
    }

    function startOAuthLogin(provider) {
        log("startOAuthLogin", [provider]);
        return !fail;
    }
}
