// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// An entity type the installed manifest declares but whose QML has not
// registered yet (bus activation can answer before the page that declares
// it has loaded): lookups and searches wait for it instead of failing with
// "no entity type". Its own process, with the notes manifest
// (KEEL_ACTIONS_MANIFEST) and no note entity until the test makes one.
import QtQuick 2.15
import QtTest 1.2
import Keel.Actions 1.0

TestCase {
    id: test
    name: "KeelActionsLateEntity"
    when: windowShown

    function test_entity_calls_wait_for_registration() {
        const find = KeelActions.findEntities("note", "", 5)
        const get = KeelActions.getEntity("note", "n1")
        verify(!find.finished, find.errorMessage)
        verify(!get.finished, get.errorMessage)
        const late = Qt.createQmlObject(`
            import Keel.Actions 1.0
            KeelEntity {
                type: "note"
                title: "Note"
                onResolve: (id, call) => call.reply({ id: id, title: "Late" })
                onFind: (query, limit, call) => call.reply([{ id: "l1", title: "Late" }])
            }`, test)
        tryVerify(() => find.finished && get.finished)
        verify(find.succeeded, find.errorMessage)
        compare(find.result.items[0].title, "Late")
        verify(get.succeeded, get.errorMessage)
        compare(get.result.title, "Late")
        late.destroy()
    }

    function test_undeclared_type_still_fails_at_once() {
        const call = KeelActions.findEntities("photo", "", 5)
        verify(call.finished)
        compare(call.errorCode, "UnknownAction")
    }
}
