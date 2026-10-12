pragma ComponentBehavior: Bound

import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

MApp {
    id: messagesApp

    property var conversations: SMSService.conversations
    property string selectedConversationId: ""

    // Pin/archive state and drafts are client-side; SMSService has no store for them.
    property var pinnedIds: []
    property var archivedIds: []
    property var drafts: ({})

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

    function tintFor(name) {
        const palette = [MColors.secBlue, MColors.secRose, MColors.secViolet, MColors.secBlueD, MColors.secGreen, MColors.secAmber, MColors.elev3];
        let h = 0;
        for (let i = 0; i < name.length; ++i)
            h = (h * 31 + name.charCodeAt(i)) >>> 0;
        return palette[h % palette.length];
    }

    function setFlag(key, ids, id, on) {
        const next = ids.filter(x => x !== id);
        if (on)
            next.push(id);
        SettingsManagerCpp.set(key, JSON.stringify(next));
        return next;
    }

    function setPinned(id, on) {
        pinnedIds = setFlag("messages/pinned", pinnedIds, id, on);
    }

    function setArchived(id, on) {
        archivedIds = setFlag("messages/archived", archivedIds, id, on);
    }

    function setDraft(id, text) {
        const next = Object.assign({}, drafts);
        if (text.trim() === "")
            delete next[id];
        else
            next[id] = text;
        drafts = next;
        draftSaveTimer.restart();
    }

    function _navigateBack(page) {
        page.navigateBack();
    }

    appId: "messages"
    appName: "Messages"
    appIcon: "assets/icon.svg"

    Component.onCompleted: {
        pinnedIds = JSON.parse(SettingsManagerCpp.get("messages/pinned", "[]"));
        archivedIds = JSON.parse(SettingsManagerCpp.get("messages/archived", "[]"));
        drafts = JSON.parse(SettingsManagerCpp.get("messages/drafts", "{}"));
    }
    Component.onDestruction: if (draftSaveTimer.running)
        SettingsManagerCpp.set("messages/drafts", JSON.stringify(drafts))

    Timer {
        id: draftSaveTimer
        interval: 1000
        onTriggered: SettingsManagerCpp.set("messages/drafts", JSON.stringify(messagesApp.drafts))
    }

    Connections {
        function onMessageReceived(sender, text, timestamp) {
            Logger.info("Messages", "New message from: " + sender);
            const match = messagesApp.conversations.find(c => MPhoneNumber.sameNumber(c.contactNumber, sender));
            if (match && messagesApp.archivedIds.indexOf(match.id) !== -1)
                messagesApp.setArchived(match.id, false);
        }

        target: SMSService
    }

    Connections {
        function onConversationsChanged() {
            Logger.info("Messages", "Conversations updated");
            messagesApp.refreshConversations();
        }

        target: SMSService
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack

            anchors.fill: parent
            initialItem: listPage
        }

        Binding {
            target: messagesApp
            property: "navigationDepth"
            value: navigationStack.depth - 1 + (listPage.sheetOpen ? 1 : 0)
        }

        Connections {
            function onBackPressed() {
                if (navigationStack.depth > 1)
                    messagesApp._navigateBack(navigationStack.currentItem);
                else if (listPage.sheetOpen)
                    listPage.closeSheet();
            }

            target: messagesApp
        }

        ConversationsListPage {
            id: listPage

            app: messagesApp

            onOpenConversation: function (conversationId) {
                messagesApp.selectedConversationId = conversationId;
                var conversation = messagesApp.getConversation(conversationId);
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

        Component {
            id: chatPage

            ChatPage {
                app: messagesApp
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
                    var conversation = messagesApp.conversations.find(c => MPhoneNumber.sameNumber(c.contactNumber, recipient)) || {
                        "id": SMSService.generateConversationId(recipient),
                        "contactName": recipientName,
                        "contactNumber": recipient,
                        "lastMessage": "",
                        "timestamp": Date.now(),
                        "unread": false
                    };
                    navigationStack.replace(chatPage, {
                        "conversation": conversation
                    });
                }
                onNavigateBack: function () {
                    navigationStack.pop();
                }
            }
        }
    }
}
