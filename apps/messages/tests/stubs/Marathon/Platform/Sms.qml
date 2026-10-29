pragma Singleton
import QtQml

QtObject {
    property var conversations: []
    property var messages: ({})
    property var sent: []
    property var deleted: []
    property var deletedMessages: []
    property var read: []
    property bool mmsAvailable: true
    property var sentMms: []
    property var opened: []

    signal messageReceived(string sender, string text, real timestamp)
    signal messageSent(string recipient, real timestamp)
    signal sendFailed(string recipient, string reason)
    signal messageStatusChanged(int id, string status)

    function reset(convs, msgs) {
        conversations = convs || [];
        messages = msgs || {};
        sent = [];
        deleted = [];
        deletedMessages = [];
        read = [];
        sentMms = [];
        opened = [];
        mmsAvailable = true;
    }
    function getMessages(id) {
        return messages[id] || [];
    }
    function sendMessage(recipient, text) {
        sent = sent.concat([
            {
                recipient: recipient,
                text: text
            }
        ]);
    }
    function deleteConversation(id) {
        deleted = deleted.concat([id]);
        conversations = conversations.filter(c => c.id !== id);
    }
    function deleteMessage(id) {
        deletedMessages = deletedMessages.concat([id]);
        for (const conv in messages)
            messages[conv] = messages[conv].filter(m => m.id !== id);
        return true;
    }
    function markAsRead(id) {
        read = read.concat([id]);
    }
    function sendMms(recipients, text, attachments) {
        sentMms = sentMms.concat([
            {
                recipients: recipients,
                text: text,
                attachments: attachments
            }
        ]);
        return 100 + sentMms.length;
    }
    function openAttachment(id, name) {
        opened = opened.concat([id]);
        return "/cache/mms/" + id + "/" + name;
    }
    function generateConversationId(number) {
        return "conv_" + number;
    }
}
