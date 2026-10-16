import QtQuick
import Keel.Actions 1.0
import "NotesStore.js" as Store

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml NotesActions.qml --qml pages/NoteEditorPage.qml \
//       --app-id org.marathonos.notes --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: notes and save(next).
    property var store

    function summary(note) {
        const text = Store.text(note);
        return {
            id: note.id,
            title: Store.titleOf(text).substring(0, 200),
            body: text.substring(0, 2000),
            modified: new Date(Number(note.timestamp) || 0).toISOString()
        };
    }

    KeelAction {
        name: "notes.create"
        title: qsTr("Create note")
        description: "Create a note in Marathon Notes. The title becomes the note's first line, followed by the body. Returns the new note's id."
        idempotent: false
        parameters: [
            KeelParam { name: "title"; type: "string"; maxLength: 200; description: "Title of the note" },
            KeelParam { name: "body"; type: "string"; required: true; maxLength: 20000; description: "Text of the note" }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "id"; type: "integer"; minimum: 1; required: true }
        }
        onInvoked: (args, call) => {
            const title = String(args.title || "").trim();
            const next = Store.create(root.store.notes, title ? title + "\n" + args.body : args.body, Date.now());
            root.store.save(next);
            call.reply({ id: next[0].id });
        }
    }

    KeelAction {
        name: "notes.search"
        title: qsTr("Search notes")
        description: "Search Marathon Notes for text in a note's title or body; an empty query lists every note. Returns up to `limit` notes, pinned first, then the most recently changed, each with its id, title, text (the first 2000 characters) and when it was last changed."
        readOnly: true
        idempotent: true
        parameters: [
            KeelParam { name: "query"; type: "string"; required: true; maxLength: 256 },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 50; defaultValue: 10 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam { name: "id"; type: "integer"; minimum: 1; required: true }
            KeelParam { name: "title"; type: "string"; maxLength: 200; required: true }
            KeelParam { name: "body"; type: "string"; maxLength: 2000; required: true }
            KeelParam { name: "modified"; type: "string"; format: "date-time"; maxLength: 32; required: true }
        }
        onInvoked: (args, call) => {
            const found = Store.sorted(Store.search(root.store.notes, args.query));
            call.reply(found.slice(0, args.limit || 10).map(root.summary));
        }
    }
}
