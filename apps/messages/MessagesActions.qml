import QtQuick
import Keel.Actions 1.0
import Marathon.Platform 1.0
import "MessagesLogic.js" as Logic

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml MessagesActions.qml \
//       --app-id org.marathonos.messages --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: conversations, pinnedIds, archivedIds and conversationFor().
    property var app
    // messages.send calls waiting for Sms to report: [{ number, call }].
    property var sending: []

    // A call that timed out is already deleted (null here).
    function settle(recipient, answer) {
        const done = sending.filter(s => recipient === "" || Logic.sameNumber(s.number, recipient));
        sending = sending.filter(s => s.call && done.indexOf(s) === -1);
        done.forEach(s => s.call && answer(s.call));
    }

    Connections {
        target: Sms

        function onMessageSent(recipient, timestamp) {
            root.settle(recipient, call => call.reply({ sent: new Date(timestamp).toISOString() }));
        }
        function onSendFailed(recipient, reason) {
            root.settle(recipient, call => call.fail("Failed", reason));
        }
    }

    KeelAction {
        name: "conversations.search"
        title: qsTr("Search conversations")
        description: "Search the text message conversations in Marathon Messages by the contact's name or number or the last message; an empty query lists them all. Returns up to `limit` conversations, pinned first, then the most recent, each with the contact's name and number, the last message, when it arrived and how many messages are unread. Archived conversations are left out."
        readOnly: true
        idempotent: true
        untrusted: true
        parameters: [
            KeelParam { name: "query"; type: "string"; required: true; maxLength: 256 },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 50; defaultValue: 10 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam { name: "name"; type: "string"; maxLength: 200; required: true }
            KeelParam { name: "number"; type: "string"; maxLength: 64; required: true }
            KeelParam { name: "lastMessage"; type: "string"; maxLength: 2000; required: true }
            KeelParam { name: "time"; type: "string"; format: "date-time"; maxLength: 32; required: true }
            KeelParam { name: "unread"; type: "integer"; minimum: 0; required: true }
        }
        onInvoked: (args, call) => {
            const found = Logic.visibleConversations(root.app.conversations, root.app.pinnedIds, root.app.archivedIds, false, args.query);
            call.reply(found.slice(0, args.limit || 10).map(c => ({
                name: String(c.contactName || "").substring(0, 200),
                number: String(c.contactNumber || ""),
                lastMessage: String(c.lastMessage || "").substring(0, 2000),
                time: new Date(c.lastTimestamp || 0).toISOString(),
                unread: c.unreadCount || 0
            })));
        }
    }

    KeelAction {
        name: "messages.read"
        title: qsTr("Read conversation")
        description: "Read the latest text messages exchanged with a phone number in Marathon Messages, oldest first. Each message has its text, whether the person sent it, and when. The conversation is not marked as read."
        readOnly: true
        idempotent: true
        untrusted: true
        parameters: [
            KeelParam { name: "number"; type: "string"; required: true; maxLength: 64; description: "The other person's phone number" },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 100; defaultValue: 20 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 100
            KeelParam { name: "text"; type: "string"; maxLength: 2000; required: true }
            KeelParam { name: "outgoing"; type: "boolean"; required: true }
            KeelParam { name: "time"; type: "string"; format: "date-time"; maxLength: 32; required: true }
        }
        onInvoked: (args, call) => {
            const messages = Sms.getMessages(root.app.conversationFor(args.number, "").id);
            call.reply(messages.slice(-(args.limit || 20)).map(m => ({
                text: String(m.text || "").substring(0, 2000),
                outgoing: m.isOutgoing === true,
                time: new Date(m.timestamp || 0).toISOString()
            })));
        }
    }

    KeelAction {
        name: "messages.send"
        title: qsTr("Send text message")
        description: "Send a text message (SMS) from Marathon Messages to a phone number. Answers once the network has taken the message, with when it was sent."
        destructive: true
        confirm: true
        openWorld: true
        parameters: [
            KeelParam { name: "to"; type: "string"; required: true; maxLength: 64; description: "Phone number to send to" },
            KeelParam { name: "text"; type: "string"; required: true; minLength: 1; maxLength: 2000; description: "The message" }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "sent"; type: "string"; format: "date-time"; maxLength: 32; required: true }
        }
        onInvoked: (args, call) => {
            if (!Logic.isPhoneNumber(args.to)) {
                call.fail("InvalidArguments", "Not a phone number");
            } else if (!Telephony.hasModem) {
                call.fail("NotAvailable", "No SIM or modem");
            } else {
                const number = Logic.normaliseNumber(args.to);
                root.sending = root.sending.concat([{ number: number, call: call }]);
                Sms.sendMessage(number, args.text);
            }
        }
    }
}
