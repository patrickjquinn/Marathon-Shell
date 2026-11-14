// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the selection plumbing of the single-item picker pages.
// A pick sets selectedContent and selectedContentProperties on the public
// picker page (`_target`, which may be further down the stack when the user
// browsed into sub-pages) and pops back to the page below it, so the app's
// onSelectedContentPropertiesChanged handler runs and the app's page is
// shown again, as with Sailfish's pickers.
import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property string title
    property var _target: page
    // Aliases, not bindings: the change signals fire on a pick only, never
    // when the page is created (apps read filePath in the handler).
    readonly property alias selectedContent: selected.content
    readonly property alias selectedContentProperties: selected.properties

    QtObject {
        id: selected
        property url content
        property var properties
    }

    function _pick(props) {
        if (_target !== page) {
            _target._pick(props)
            return
        }
        selected.content = props.url
        selected.properties = props
        _popPast(page)
    }

    // Pops `picker` and everything above it.
    function _popPast(picker) {
        if (!pageStack)
            return
        var below = null
        try {
            below = pageStack.previousPage(picker)
        } catch (e) {
            return // not on the stack (created directly)
        }
        if (below)
            pageStack.pop(below)
        else
            pageStack.pop()
    }
}
