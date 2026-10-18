import QtQuick
import Keel.Actions 1.0
import "MailLogic.js" as Logic

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml MailActions.qml \
//       --app-id org.marathonos.email --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: mail, hasAccount and compose().
    property var app
    // DelegateModel items over app.mail.messages, the open folder.
    property var messages

    KeelAction {
        name: "mail.search"
        title: qsTr("Search mail")
        description: "Search the open folder of Marathon Mail (the inbox unless the person opened another) for text in the sender, subject or preview; an empty query lists every message. Returns up to `limit` messages, newest first, each with its id, sender, subject, preview, when it arrived as shown in the app, and whether it is unread."
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
            KeelParam { name: "id"; type: "string"; maxLength: 32; required: true }
            KeelParam { name: "from"; type: "string"; maxLength: 512; required: true }
            KeelParam { name: "subject"; type: "string"; maxLength: 1000; required: true }
            KeelParam { name: "preview"; type: "string"; maxLength: 1000; required: true }
            KeelParam { name: "received"; type: "string"; maxLength: 64; required: true }
            KeelParam { name: "unread"; type: "boolean"; required: true }
        }
        onInvoked: (args, call) => {
            if (!root.app.hasAccount) {
                call.fail("NotAvailable", "No mail account is set up");
                return;
            }
            const found = [];
            const limit = args.limit || 10;
            for (let i = 0; i < root.messages.count && found.length < limit; ++i) {
                const m = root.messages.get(i).model;
                if (Logic.matchesMessage(m, args.query))
                    found.push({
                        id: String(m.messageId),
                        from: String(m.from || "").substring(0, 512),
                        subject: String(m.subject || "").substring(0, 1000),
                        preview: String(m.snippet || "").substring(0, 1000),
                        received: String(m.timestamp || "").substring(0, 64),
                        unread: m.unread === true
                    });
            }
            call.reply(found);
        }
    }

    KeelAction {
        name: "mail.read"
        title: qsTr("Read email")
        description: "Read one email in Marathon Mail by the id mail.search returned: sender, recipients, subject, date and text (the first 20000 characters). The message is not marked as read."
        readOnly: true
        idempotent: true
        untrusted: true
        parameters: [
            KeelParam { name: "id"; type: "string"; required: true; maxLength: 32; pattern: "^[0-9]+$" }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "from"; type: "string"; maxLength: 512; required: true }
            KeelParam { name: "to"; type: "array"; itemType: "string"; maxItems: 100; maxLength: 512; required: true }
            KeelParam { name: "subject"; type: "string"; maxLength: 1000; required: true }
            KeelParam { name: "date"; type: "string"; format: "date-time"; maxLength: 32 }
            KeelParam { name: "body"; type: "string"; maxLength: 20000; required: true }
        }
        onInvoked: (args, call) => {
            const msg = root.app.mail.openMessage(args.id);
            if (msg.from === undefined) {
                call.fail("Failed", "No message with that id");
                return;
            }
            const html = String(msg.bodyHtml || "").replace(/<style[\s\S]*?<\/style>|<[^>]*>/gi, " ").replace(/\s+/g, " ").trim();
            const out = {
                from: String(msg.from).substring(0, 512),
                to: (msg.to || []).slice(0, 100).map(a => String(a).substring(0, 512)),
                subject: String(msg.subject || "").substring(0, 1000),
                body: (msg.bodyPlain || html).substring(0, 20000)
            };
            const date = new Date(msg.date);
            if (!isNaN(date))
                out.date = date.toISOString();
            call.reply(out);
        }
    }

    KeelAction {
        name: "mail.compose"
        title: qsTr("Write email")
        description: "Open a new email in Marathon Mail with the recipients, subject and text filled in, for the person to check and send."
        notDestructiveBecause: "it only opens a draft; nothing leaves the phone until the person sends it"
        parameters: [
            KeelParam { name: "to"; type: "string"; maxLength: 2000; description: "Recipients' addresses, separated by commas" },
            KeelParam { name: "cc"; type: "string"; maxLength: 2000; description: "Addresses to copy, separated by commas" },
            KeelParam { name: "subject"; type: "string"; maxLength: 1000 },
            KeelParam { name: "body"; type: "string"; maxLength: 100000 }
        ]
        onInvoked: (args, call) => {
            root.app.activate();
            root.app.compose({
                defaultTo: args.to || "",
                defaultCc: args.cc || "",
                defaultSubject: args.subject || "",
                defaultBody: args.body || ""
            });
            call.reply();
        }
    }
}
