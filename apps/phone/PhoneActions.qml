import QtQuick
import Keel.Actions 1.0
import Marathon.Platform 1.0
import "Phone.js" as Phone

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml PhoneActions.qml \
//       --app-id org.marathonos.phone --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: callHistory, contacts, hasContactsPermission, inCall, emergencyOnly, contactName(), call().
    property var phone

    KeelAction {
        name: "calls.recent"
        title: qsTr("Recent calls")
        description: "List the most recent calls in the Phone app's call log, newest first, optionally only one type (incoming, outgoing, missed or rejected). Each call has the number, the contact's name if known, the type, when it happened and how long it lasted in seconds."
        readOnly: true
        idempotent: true
        // The lock screen's emergency dialer offers none of these.
        enabled: !root.phone.emergencyOnly
        parameters: [
            KeelParam { name: "type"; type: "string"; values: ["incoming", "outgoing", "missed", "rejected"] },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 50; defaultValue: 10 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam { name: "number"; type: "string"; maxLength: 64; required: true }
            KeelParam { name: "name"; type: "string"; maxLength: 200; required: true }
            KeelParam { name: "type"; type: "string"; maxLength: 16; required: true }
            KeelParam { name: "time"; type: "string"; format: "date-time"; maxLength: 32; required: true }
            KeelParam { name: "duration"; type: "integer"; minimum: 0; required: true }
        }
        onInvoked: (args, call) => {
            const calls = root.phone.callHistory.filter(c => !args.type || c.type === args.type);
            call.reply(calls.slice(0, args.limit || 10).map(c => ({
                number: String(c.number || ""),
                name: String(c.contactName || root.phone.contactName(c.number)),
                type: String(c.type),
                time: new Date(Phone.timestampMs(c.timestamp)).toISOString(),
                duration: Math.max(0, Math.floor(Number(c.duration) || 0))
            })));
        }
    }

    KeelAction {
        name: "contacts.find"
        title: qsTr("Find contacts")
        description: "Find people in the Phone app's contacts whose name or number contains the query. Returns up to `limit` contacts, each with name, phone number and email address."
        readOnly: true
        idempotent: true
        enabled: !root.phone.emergencyOnly
        parameters: [
            KeelParam { name: "query"; type: "string"; required: true; maxLength: 256 },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 50; defaultValue: 10 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam { name: "name"; type: "string"; maxLength: 200; required: true }
            KeelParam { name: "phone"; type: "string"; maxLength: 64; required: true }
            KeelParam { name: "email"; type: "string"; maxLength: 256; required: true }
        }
        onInvoked: (args, call) => {
            if (!root.phone.hasContactsPermission) {
                call.fail("NotAvailable", "Phone has not been allowed to read contacts");
                return;
            }
            call.reply(Phone.peopleRows(root.phone.contacts, args.query).slice(0, args.limit || 10).map(c => ({
                name: String(c.name || ""),
                phone: String(c.phone || ""),
                email: String(c.email || "")
            })));
        }
    }

    KeelAction {
        name: "call.dial"
        title: qsTr("Call")
        description: "Call a phone number from the Phone app: the call starts at once and the call screen comes to the front."
        confirm: true
        openWorld: true
        enabled: !root.phone.emergencyOnly
        parameters: [
            KeelParam { name: "number"; type: "string"; required: true; maxLength: 64; description: "Phone number to call" }
        ]
        onInvoked: (args, call) => {
            const number = Phone.dialable(args.number);
            if (number === "") {
                call.fail("InvalidArguments", "Not a phone number");
            } else if (root.phone.inCall) {
                call.fail("NotAvailable", "A call is already in progress");
            } else if (!Telephony.hasModem && !Phone.isEmergency(number)) {
                call.fail("NotAvailable", "No SIM or modem");
            } else {
                root.phone.activate();
                root.phone.call(number);
                call.reply();
            }
        }
    }
}
