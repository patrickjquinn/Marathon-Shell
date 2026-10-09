// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel.Actions: declarations, validation, dispatch, entities, context and
// the manifest the runtime describes (KEEL_ACTIONS_APP_ID=org.example.notes).
import QtQuick 2.15
import QtTest 1.2
import Keel.Actions 1.0
import "../app"

TestCase {
    id: test
    name: "KeelActions"
    when: windowShown

    NotesActions { id: app }

    function invoke(name, args) {
        return KeelActions.invoke(name, args)
    }

    function tool(manifest, name) {
        for (const t of manifest.tools) {
            if (t.name === "org.example.notes/" + name)
                return t
        }
        return null
    }

    function test_appId() {
        compare(KeelActions.appId, "org.example.notes")
        compare(KeelActions.headless, false)
    }

    function test_create_and_reply() {
        const call = invoke("notes.create", { title: "Hello", body: "World" })
        verify(call.finished)
        verify(call.succeeded, call.errorMessage)
        compare(call.result.id, "n3")
        compare(call.result.note, "keel://org.example.notes/note/n3")
        compare(app.notes.length, 3)
    }

    function test_invalid_arguments_data() {
        return [
            { tag: "missing required", args: { title: "x" } },
            { tag: "too long", args: { body: "x".repeat(20001) } },
            { tag: "wrong type", args: { body: 5 } },
            { tag: "unknown property", args: { body: "x", colour: "red" } }
        ]
    }

    function test_invalid_arguments(data) {
        const before = app.notes.length
        const call = invoke("notes.create", data.args)
        verify(call.finished)
        compare(call.errorCode, "InvalidArguments")
        verify(call.errorMessage.length > 0)
        compare(app.notes.length, before)
    }

    function test_unknown_action() {
        const call = invoke("notes.fly", {})
        compare(call.errorCode, "UnknownAction")
    }

    function test_wrapped_array_result() {
        const call = invoke("notes.search", { query: "anna" })
        verify(call.succeeded, call.errorMessage)
        compare(call.result.result, ["keel://org.example.notes/note/n2"])
    }

    function test_integer_bounds() {
        compare(invoke("notes.search", { query: "a", limit: 0 }).errorCode, "InvalidArguments")
        compare(invoke("notes.search", { query: "a", limit: 1.5 }).errorCode, "InvalidArguments")
        verify(invoke("notes.search", { query: "a", limit: 50 }).succeeded)
    }

    function test_entity_reference_argument() {
        compare(invoke("notes.delete", { note: "n1" }).errorCode, "InvalidArguments")
        compare(invoke("notes.delete", { note: "keel://org.example.other/note/n1" }).errorCode, "InvalidArguments")
        const failed = invoke("notes.delete", { note: "keel://org.example.notes/note/zz" })
        compare(failed.errorCode, "Failed")
        compare(failed.errorMessage, "no such note")
        const call = invoke("notes.delete", { note: "keel://org.example.notes/note/n2" })
        verify(call.succeeded, call.errorMessage)
        compare(JSON.stringify(call.result), "{}")
        verify(app.findNote("n2") === null)
        app.notes = app.notes.concat([{ id: "n2", title: "Trattoria Anna", body: "Via Roma 1, booked for Friday", tags: ["food"], created: "2026-09-25T19:30:00Z" }])
    }

    function test_result_must_match_schema() {
        const call = invoke("notes.broken", {})
        compare(call.errorCode, "Failed")
        verify(call.errorMessage.indexOf("schema") >= 0, call.errorMessage)
    }

    function test_asynchronous_reply() {
        const call = invoke("notes.later", { text: "soon" })
        verify(!call.finished)
        tryCompare(call, "finished", true, 2000)
        compare(call.result.result, "soon")
    }

    function test_timeout() {
        const call = invoke("notes.share", { note: "keel://org.example.notes/note/n1", to: "keel://org.example.contacts/contact/c1" })
        verify(!call.finished)
        tryCompare(call, "finished", true, 2000)
        compare(call.errorCode, "Timeout")
    }

    function test_disabled_action() {
        app.createEnabled = false
        compare(invoke("notes.create", { body: "x" }).errorCode, "NotAvailable")
        app.createEnabled = true
    }

    function test_entity_lookup() {
        const call = KeelActions.getEntity("note", "n1")
        verify(call.succeeded, call.errorMessage)
        compare(call.result.uri, "keel://org.example.notes/note/n1")
        compare(call.result.title, "Shopping")
        compare(call.result.body, "Milk, bread")
        compare(KeelActions.getEntity("note", "nope").errorCode, "NotAvailable")
        compare(KeelActions.getEntity("note", "a/b").errorCode, "InvalidArguments")
        compare(KeelActions.getEntity("photo", "n1").errorCode, "UnknownAction")
    }

    function test_entity_find_returns_summaries() {
        const call = KeelActions.findEntities("note", "", 1)
        verify(call.succeeded, call.errorMessage)
        compare(call.result.items.length, 1)
        const item = call.result.items[0]
        compare(item.uri, "keel://org.example.notes/note/n1")
        compare(item.created, "2026-10-01T09:00:00Z")
        compare(item.tags, ["home"])
        // Not summarisable: never in a find result.
        verify(item.body === undefined)
    }

    function test_context() {
        let ctx = KeelActions.context()
        compare(ctx.app, "org.example.notes")
        compare(ctx.purpose, "reading a note")
        compare(ctx.entity, "keel://org.example.notes/note/n1")
        compare(ctx.text, "Shopping: Milk, bread")
        app.contextText = "x".repeat(5000)
        compare(KeelActions.context().text.length, 4000)
        app.contextActive = false
        compare(JSON.stringify(KeelActions.context()), "{}")
        app.contextActive = true
        app.contextText = "Shopping: Milk, bread"
    }

    function test_describe() {
        const m = KeelActions.describe()
        compare(m.version, 1)
        compare(m.appId, "org.example.notes")
        compare(m.context.uri, "keel://org.example.notes/context")

        const create = tool(m, "notes.create")
        compare(create.title, "Create note")
        compare(create.inputSchema.type, "object")
        compare(create.inputSchema.additionalProperties, false)
        compare(create.inputSchema.required, ["body"])
        compare(create.inputSchema.properties.body.maxLength, 20000)
        compare(create.outputSchema.required, ["id", "note"])
        compare(create.outputSchema.properties.id.maxLength, 4096)
        compare(create.outputSchema.properties.note.$ref, "#/$defs/org.example.notes.note")
        const def = create.outputSchema.$defs["org.example.notes.note"]
        compare(def["x-keel-entity"], "org.example.notes/note")
        compare(def.pattern, "^keel://org\\.example\\.notes/note/[^/?#\\s]{1,256}$")
        compare(create._meta["org.shipwright.keel/result"], "object")
        compare(create.annotations.readOnlyHint, false)

        const search = tool(m, "notes.search")
        compare(search.annotations.readOnlyHint, true)
        compare(search._meta["org.shipwright.keel/result"], "wrapped")
        compare(search.outputSchema.properties.result.maxItems, 50)
        compare(search.inputSchema.properties.limit.default, 10)

        const del = tool(m, "notes.delete")
        compare(del.annotations.destructiveHint, true)
        verify(del.outputSchema === undefined)

        const share = tool(m, "notes.share")
        compare(share.annotations.openWorldHint, true)
        compare(share._meta["org.shipwright.keel/confirm"], true)
        compare(share.inputSchema.$defs["org.example.contacts.contact"]["x-keel-entity"], "org.example.contacts/contact")

        const find = tool(m, "note.find")
        compare(find.annotations.readOnlyHint, true)
        compare(find._meta["org.shipwright.keel/find"], "note")
        const summary = find.outputSchema.properties.items.items
        verify(summary.properties.created !== undefined)
        verify(summary.properties.body === undefined)

        compare(m.entities.length, 1)
        compare(m.entities[0].uriTemplate, "keel://org.example.notes/note/{id}")
        verify(m.entities[0].schema.properties.body !== undefined)
        compare(m.entities[0].schema.properties.tags["x-keel-indexable"], true)

        compare(m.prompts.length, 1)
        compare(m.prompts[0].name, "org.example.notes/shopping-list")
        compare(m.prompts[0].arguments[0].name, "items")
        compare(m.prompts[0].arguments[0].required, true)
        const steps = m.prompts[0]._meta["org.shipwright.keel/steps"]
        compare(steps[0].tool, "org.example.notes/notes.create")
        compare(steps[0].arguments.body, "{{items}}")
    }

    function test_array_of_objects() {
        const action = Qt.createQmlObject(`
            import Keel.Actions 1.0
            KeelAction {
                name: "weather.forecast"
                description: "Get the forecast for a place for the next days."
                readOnly: true
                parameters: [ KeelParam { name: "days"; type: "integer"; minimum: 1; maximum: 7; defaultValue: 3 } ]
                returns: KeelResult {
                    type: "array"; itemType: "object"; maxItems: 7
                    KeelParam { name: "date"; type: "string"; format: "date"; maxLength: 10; required: true }
                    KeelParam { name: "summary"; type: "string"; maxLength: 200; required: true }
                }
                onInvoked: (args, call) => call.reply(args.days === 2
                    ? [{ date: "2026-10-03", summary: "Rain" }, { date: "2026-10-04", summary: "Sun" }]
                    : [{ date: "2026-10-03" }])
            }`, test)
        const t = tool(KeelActions.describe(), "weather.forecast")
        const items = t.outputSchema.properties.result.items
        compare(items.type, "object")
        compare(items.required, ["date", "summary"])
        compare(items.properties.date.format, "date")
        const ok = KeelActions.invoke("weather.forecast", { days: 2 })
        verify(ok.succeeded, ok.errorMessage)
        compare(ok.result.result.length, 2)
        // A missing required field in the answer is the app's bug.
        compare(KeelActions.invoke("weather.forecast", {}).errorCode, "Failed")
        compare(KeelActions.invoke("weather.forecast", { days: 8 }).errorCode, "InvalidArguments")
        action.destroy()
        wait(0)
        compare(KeelActions.invoke("weather.forecast", {}).errorCode, "UnknownAction")
    }

    function test_handler_exception_fails_at_once() {
        const action = Qt.createQmlObject(`
            import Keel.Actions 1.0
            KeelAction {
                name: "test.throws"
                description: "Test action whose handler throws a JavaScript exception."
                returns: KeelResult { type: "string"; maxLength: 8 }
                onInvoked: (args, call) => { undefinedFunction() }
            }`, test)
        ignoreWarning(/undefinedFunction is not defined/)
        const call = KeelActions.invoke("test.throws", {})
        verify(call.finished, "no waiting for the timeout")
        compare(call.errorCode, "Failed")
        verify(call.errorMessage.indexOf("undefinedFunction") >= 0, call.errorMessage)
        action.destroy()
    }

    function test_invoke_on_declaration() {
        // KeelAction.invoke() takes the same path as KeelActions.invoke().
        const call = app.createAction.invoke({ body: "from the declaration" })
        verify(call.succeeded, call.errorMessage)
        compare(app.createAction.invoke({}).errorCode, "InvalidArguments")
    }
}
