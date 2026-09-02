import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

MApp {
    id: messagesApp

    property var conversations: SMSService.conversations
    property string selectedConversationId: ""

    function getConversation(id) {
        if (id === undefined || id === null)
            return null;

        for (var i = 0; i < conversations.length; i++) {
            var conversation = conversations[i];
            if (conversation.id === id || conversation.contactNumber === id)
                return conversation;
        }
        Logger.warn("Messages", "Conversation not found: " + id);
        return null;
    }

    function refreshConversations() {
        conversations = SMSService.conversations;
    }

    function formatTimestamp(timestamp) {
        var now = Date.now();
        var diff = now - timestamp;
        if (diff < 1000 * 60 * 60)
            return Math.floor(diff / (1000 * 60)) + "m";
        else if (diff < 1000 * 60 * 60 * 24)
            return Math.floor(diff / (1000 * 60 * 60)) + "h";
        else
            return Math.floor(diff / (1000 * 60 * 60 * 24)) + "d";
    }

    appId: "messages"
    appName: "Messages"
    appIcon: "assets/icon.svg"

    Connections {
        function onMessageReceived(sender, text, timestamp) {
            Logger.info("Messages", "New message from: " + sender);
        }

        target: SMSService
    }

    Connections {
        function onConversationsChanged() {
            Logger.info("Messages", "Conversations updated");
            refreshConversations();
        }

        target: SMSService
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack

            property var backConnection: null

            anchors.fill: parent
            initialItem: conversationsListPage
            onDepthChanged: {
                messagesApp.navigationDepth = depth - 1;
            }
            Component.onCompleted: {
                messagesApp.navigationDepth = depth - 1;
                backConnection = messagesApp.backPressed.connect(function () {
                    if (depth > 1)
                        pop();
                });
            }
            Component.onDestruction: {
                if (backConnection)
                    messagesApp.backPressed.disconnect(backConnection);
            }
        }

        Component {
            id: conversationsListPage

            ConversationsListPage {
                onOpenConversation: function (conversationId) {
                    selectedConversationId = conversationId;
                    var conversation = getConversation(conversationId);
                    if (conversation)
                        navigationStack.push(chatPage, {
                            "conversation": conversation
                        });
                    else
                        Logger.warn("Messages", "Conversation not found: " + conversationId);
                }
                onNewMessage: function () {
                    navigationStack.push(newConversationPage);
                }
            }
        }

        Component {
            id: chatPage

            ChatPage {
                onNavigateBack: {
                    navigationStack.pop();
                }
            }
        }

        Component {
            id: newConversationPage

            NewConversationPage {
                onConversationStarted: function (recipient, recipientName) {
                    Logger.info("Messages", "Starting conversation with: " + recipient);
                    var conversationId = SMSService.generateConversationId(recipient);
                    var conversation = {
                        "id": conversationId,
                        "contactName": recipientName,
                        "contactNumber": recipient,
                        "lastMessage": "",
                        "timestamp": Date.now(),
                        "unread": false
                    };
                    navigationStack.pop();
                    navigationStack.push(chatPage, {
                        "conversation": conversation
                    });
                }
                onCancelled: function () {
                    navigationStack.pop();
                }
            }
        }
    }
}
