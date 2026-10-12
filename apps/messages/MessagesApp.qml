pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Configuration 1.0
import "MessagesLogic.js" as Logic
import "pages"
import "cover"

ApplicationWindow {
    id: root

    // Pins, archive and drafts are client-side; Sms has no store for them.
    property QtObject store: ConfigurationValue {
        key: "/apps/messages/state"
        defaultValue: "{}"
    }
    property string route: typeof MARATHON_APP_ROUTE !== "undefined" ? MARATHON_APP_ROUTE : ""
    property string routeParams: typeof MARATHON_APP_ROUTE_PARAMS !== "undefined" ? MARATHON_APP_ROUTE_PARAMS : ""
    readonly property var conversations: Sms.conversations
    property var pinnedIds: []
    property var archivedIds: []
    property var drafts: ({})

    function save() {
        draftTimer.stop();
        store.value = JSON.stringify({ pinned: pinnedIds, archived: archivedIds, drafts: drafts });
    }

    function toggled(ids, id, on) {
        const next = ids.filter(x => x !== id);
        if (on)
            next.push(id);
        return next;
    }

    function setPinned(id, on) {
        pinnedIds = toggled(pinnedIds, id, on);
        save();
    }

    function setArchived(id, on) {
        archivedIds = toggled(archivedIds, id, on);
        save();
    }

    function setDraft(id, text) {
        if ((drafts[id] || "") === text.trim())
            return;
        const next = Object.assign({}, drafts);
        if (text.trim() === "")
            delete next[id];
        else
            next[id] = text.trim();
        drafts = next;
        draftTimer.restart();
    }

    function deleteConversation(id) {
        pinnedIds = toggled(pinnedIds, id, false);
        archivedIds = toggled(archivedIds, id, false);
        const next = Object.assign({}, drafts);
        delete next[id];
        drafts = next;
        save();
        Sms.deleteConversation(id);
    }

    function openConversation(conversation) {
        pageStack.push(Qt.resolvedUrl("pages/ConversationPage.qml"), { app: root, conversation: conversation });
    }

    function newMessage() {
        pageStack.push(Qt.resolvedUrl("pages/NewMessagePage.qml"), { app: root });
    }

    function conversationFor(number, name) {
        return conversations.find(c => Logic.sameNumber(c.contactNumber, number)) || {
            id: Sms.generateConversationId(number),
            contactName: name,
            contactNumber: number,
            lastMessage: "",
            lastTimestamp: 0,
            unreadCount: 0
        };
    }

    // Replaces the recipient picker with the thread, existing or new.
    function startConversation(number, name) {
        pageStack.replace(Qt.resolvedUrl("pages/ConversationPage.qml"), { app: root, conversation: conversationFor(number, name) });
    }

    function openRoute(name, paramsJson, operation) {
        const number = name === "conversation" ? Logic.routeNumber(paramsJson) : "";
        if (number === "")
            return;
        const contact = (Contacts.contacts || []).find(c => Logic.sameNumber(c.phone, number));
        const list = pageStack.find(p => !pageStack.previousPage(p));
        if (pageStack.currentPage !== list)
            pageStack.pop(list, PageStackAction.Immediate);
        pageStack.push(Qt.resolvedUrl("pages/ConversationPage.qml"), { app: root, conversation: conversationFor(number, contact ? contact.name : "") }, operation);
    }

    appId: "messages"

    cover: Component {
        MessagesCover {
            conversations: root.conversations
            onNewMessageRequested: {
                root.activate();
                root.newMessage();
            }
        }
    }

    initialPage: Component {
        ConversationsPage {
            app: root
        }
    }

    Component.onCompleted: {
        const state = Logic.parseState(store.value);
        pinnedIds = state.pinned;
        archivedIds = state.archived;
        drafts = state.drafts;
        openRoute(route, routeParams, PageStackAction.Immediate);
    }
    Component.onDestruction: if (draftTimer.running)
        save()

    Timer {
        id: draftTimer
        interval: 1000
        onTriggered: root.save()
    }

    Connections {
        target: typeof NavigationRouter !== "undefined" ? NavigationRouter : null
        ignoreUnknownSignals: true

        function onDeepLinkRequested(appId, route, params) {
            if (appId === root.appId) {
                root.activate();
                root.openRoute(route, JSON.stringify(params || {}));
            }
        }
    }

    Connections {
        target: Sms

        function onMessageReceived(sender, text, timestamp) {
            const match = root.conversations.find(c => Logic.sameNumber(c.contactNumber, sender));
            if (match && root.archivedIds.indexOf(match.id) !== -1)
                root.setArchived(match.id, false);
        }
    }
}
