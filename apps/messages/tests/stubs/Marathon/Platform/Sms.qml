pragma Singleton
import QtQml

QtObject {
    property var conversations: []
    property var messages: ({})
    property var sent: []
    property var deleted: []
    property var read: []

    signal messageReceived(string sender, string text, real timestamp)
    signal messageSent(string recipient, real timestamp)
    signal sendFailed(string recipient, string reason)

    function reset(convs, msgs) {
        conversations = convs || [];
        messages = msgs || {};
        sent = [];
        deleted = [];
        read = [];
    }
    function getMessages(id) {
        return messages[id] || [];
    }
    function sendMessage(recipient, text) {
        sent = sent.concat([{ recipient: recipient, text: text }]);
    }
    function deleteConversation(id) {
        deleted = deleted.concat([id]);
        conversations = conversations.filter(c => c.id !== id);
    }
    function markAsRead(id) {
        read = read.concat([id]);
    }
    function generateConversationId(number) {
        return "conv_" + number;
    }
}
