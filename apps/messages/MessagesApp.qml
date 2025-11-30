import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import "pages"

MApp {
    id: messagesApp
    appId: "messages"
    appName: "Messages"
    appIcon: "assets/icon.svg"

    property var conversations: typeof SMSService !== 'undefined' ? SMSService.conversations : []

    property int selectedConversationId: -1

    Connections {
        target: typeof SMSService !== 'undefined' ? SMSService : null
        function onMessageReceived(sender, text, timestamp) {
            Logger.info("Messages", "New message from: " + sender);
        }
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack
            anchors.fill: parent
            initialItem: conversationsListPage

            property var backConnection: null

            onDepthChanged: {
                messagesApp.navigationDepth = depth - 1;
            }

            Component.onCompleted: {
                messagesApp.navigationDepth = depth - 1;

                backConnection = messagesApp.backPressed.connect(function () {
                    if (depth > 1) {
                        pop();
                    }
                });
            }

            Component.onDestruction: {
                if (backConnection) {
                    messagesApp.backPressed.disconnect(backConnection);
                }
            }

            pushEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: navigationStack.width
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
            }

            pushExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -navigationStack.width * 0.3
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.0
                    duration: Constants.animationDurationNormal
                }
            }

            popEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: -navigationStack.width * 0.3
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: Constants.animationDurationNormal
                }
            }

            popExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: navigationStack.width
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
            }
        }

        Component {
            id: conversationsListPage
            ConversationsListPage {
                onOpenConversation: function (conversationId) {
                    selectedConversationId = conversationId;
                    var conversation = getConversation(conversationId);
                    if (conversation) {
                        navigationStack.push(chatPage, {
                            conversation: conversation
                        });
                    } else {
                        Logger.warn("Messages", "Conversation not found: " + conversationId);
                    }
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
                    var conversationId = typeof SMSService !== 'undefined' ? SMSService.generateConversationId(recipient) : "conv_" + recipient;

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
                        conversation: conversation
                    });
                }
                onCancelled: function () {
                    navigationStack.pop();
                }
            }
        }
    }

    function getConversation(id) {
        if (!id)
            return null;

        for (var i = 0; i < conversations.length; i++) {
            if (conversations[i].id === id) {
                return conversations[i];
            }
        }

        Logger.warn("Messages", "Conversation not found: " + id);
        return null;
    }

    function refreshConversations() {
        if (typeof SMSService !== 'undefined') {
            conversations = SMSService.conversations;
        }
    }

    Connections {
        target: typeof SMSService !== 'undefined' ? SMSService : null
        function onConversationsChanged() {
            Logger.info("Messages", "Conversations updated");
            refreshConversations();
        }
    }

    function formatTimestamp(timestamp) {
        var now = Date.now();
        var diff = now - timestamp;

        if (diff < 1000 * 60 * 60) {
            return Math.floor(diff / (1000 * 60)) + "m";
        } else if (diff < 1000 * 60 * 60 * 24) {
            return Math.floor(diff / (1000 * 60 * 60)) + "h";
        } else {
            return Math.floor(diff / (1000 * 60 * 60 * 24)) + "d";
        }
    }
}
