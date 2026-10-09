// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The Keel Actions test app's declarations: a small notes app with actions,
// a note entity, a context and a shortcut. Used by the QML tests, the D-Bus
// round trip and keel-mcp's conformance test, and as the generator's QML
// golden input.
import QtQuick 2.15
import Keel.Actions 1.0

Item {
    id: root

    property var notes: [
        { id: "n1", title: "Shopping", body: "Milk, bread", tags: ["home"], created: "2026-10-01T09:00:00Z" },
        { id: "n2", title: "Trattoria Anna", body: "Via Roma 1, booked for Friday", tags: ["food"], created: "2026-09-25T19:30:00Z" }
    ]
    property alias contextText: pageContext.text
    property alias contextActive: pageContext.active
    property alias contextEntity: pageContext.entity
    property alias createEnabled: createAction.enabled
    property alias createAction: createAction
    property int nextId: 3

    function findNote(id) {
        for (let i = 0; i < notes.length; ++i) {
            if (notes[i].id === id)
                return notes[i]
        }
        return null
    }

    KeelAction {
        id: createAction
        name: "notes.create"
        title: qsTr("Create note")
        description: "Create a new note with an optional title and a body. Returns the new note's id and its keel:// reference."
        idempotent: false
        parameters: [
            KeelParam { name: "title"; type: "string"; maxLength: 200; description: "Title of the note" },
            KeelParam { name: "body"; type: "string"; required: true; maxLength: 20000; description: "Text of the note" }
        ]
        returns: KeelResult {
            type: "object"
            fields: ["id"]
            KeelParam { name: "note"; type: "entity"; entity: "note"; required: true }
        }
        onInvoked: (args, call) => {
            const id = "n" + root.nextId++
            root.notes = root.notes.concat([{ id: id, title: args.title || "", body: args.body, tags: [], created: "2026-10-02T12:00:00Z" }])
            call.reply({ id: id, note: noteEntity.uri(id) })
        }
    }

    KeelAction {
        name: "notes.search"
        title: qsTr("Search notes")
        description: "Search notes by text in their title and body. Returns up to `limit` matching notes, newest first."
        readOnly: true
        idempotent: true
        parameters: [
            KeelParam { name: "query"; type: "string"; required: true; maxLength: 256 },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 50; defaultValue: 10 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "entity"
            entity: "note"
            maxItems: 50
        }
        onInvoked: (args, call) => {
            const q = args.query.toLowerCase()
            const out = []
            for (const n of root.notes) {
                if ((n.title + " " + n.body).toLowerCase().indexOf(q) >= 0 && out.length < (args.limit || 10))
                    out.push(noteEntity.uri(n.id))
            }
            call.reply(out)
        }
    }

    KeelAction {
        name: "notes.delete"
        title: qsTr("Delete note")
        description: "Delete a note permanently. The note cannot be restored afterwards."
        destructive: true
        parameters: [
            KeelParam { name: "note"; type: "entity"; entity: "note"; required: true }
        ]
        onInvoked: (args, call) => {
            const id = args.note.substring(args.note.lastIndexOf("/") + 1)
            if (!root.findNote(id)) {
                call.fail("Failed", "no such note")
                return
            }
            root.notes = root.notes.filter(n => n.id !== id)
        }
    }

    KeelAction {
        name: "notes.share"
        title: qsTr("Share note")
        description: "Send a note's text to a contact by e-mail. The note leaves the device."
        openWorld: true
        confirm: true
        notDestructiveBecause: "It sends a copy; the note itself is unchanged."
        timeout: 200
        parameters: [
            KeelParam { name: "note"; type: "entity"; entity: "note"; required: true },
            KeelParam { name: "to"; type: "entity"; entity: "org.example.contacts/contact"; required: true }
        ]
        returns: KeelResult { type: "string"; maxLength: 64 }
        // Never answers: the timeout test.
        onInvoked: (args, call) => {}
    }

    KeelAction {
        name: "notes.broken"
        description: "Test action whose handler answers with a value that does not match its schema."
        readOnly: true
        returns: KeelResult { type: "integer"; minimum: 0; maximum: 10 }
        onInvoked: (args, call) => call.reply("eleven")
    }

    KeelAction {
        name: "notes.later"
        description: "Test action that answers asynchronously, after a short timer, with the text it was given."
        readOnly: true
        parameters: [ KeelParam { name: "text"; type: "string"; required: true; maxLength: 32 } ]
        returns: KeelResult { type: "string"; maxLength: 32 }
        onInvoked: (args, call) => {
            laterTimer.call = call
            laterTimer.start()
        }
    }

    Timer {
        id: laterTimer
        property var call
        interval: 20
        onTriggered: call.reply(call.arguments.text)
    }

    KeelEntity {
        id: noteEntity
        type: "note"
        title: "Note"
        description: "A note: a title and a body of text, with tags."
        KeelParam { name: "created"; type: "string"; format: "date-time"; maxLength: 32; summarisable: true; indexable: true }
        KeelParam { name: "tags"; type: "array"; maxItems: 20; maxLength: 40; summarisable: true; indexable: true }
        KeelParam { name: "body"; type: "string"; maxLength: 20000 }
        onResolve: (id, call) => call.reply(root.findNote(id))
        onFind: (query, limit, call) => {
            const q = query.toLowerCase()
            call.reply(root.notes.filter(n => (n.title + " " + n.body).toLowerCase().indexOf(q) >= 0))
        }
    }

    KeelContext {
        id: pageContext
        purpose: "reading a note"
        entity: noteEntity.uri("n1")
        text: "Shopping: Milk, bread"
        active: true
    }

    KeelShortcut {
        name: "shopping-list"
        title: qsTr("New shopping list")
        description: "Create a note titled Shopping with the items given."
        arguments: [ KeelParam { name: "items"; type: "string"; required: true; description: "What to buy" } ]
        steps: [ { action: "notes.create", arguments: { title: "Shopping", body: "{{items}}" } } ]
    }
}
