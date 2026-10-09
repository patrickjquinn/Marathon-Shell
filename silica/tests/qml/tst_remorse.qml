// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// RemorsePopup / RemorseItem / Remorse: timeout triggers, tap cancels.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

// As in an app: the remorse popup and the list item are on the current page
// of an ApplicationWindow (a Page outside a page stack is not visible).
ApplicationWindow {
    id: root
    width: 540
    height: 960
    property var log: []

    initialPage: Component {
        Page {
            RemorsePopup {
                objectName: "popup"
                onTriggered: root.log.push("triggered")
                onCanceled: root.log.push("canceled")
            }
            ListItem {
                objectName: "listItem"
                y: 300
                Label { text: "item" }
            }
        }
    }

    TestCase {
        name: "Remorse"
        when: windowShown

        property Item page: root.pageStack.currentPage
        property Item popup: page ? findChild(page, "popup") : null
        property Item listItem: page ? findChild(page, "listItem") : null

        function init() { root.log = [] }

        function test_timeout_triggers() {
            var called = 0
            popup.execute("Deleted", function() { called++ }, 150)
            verify(popup.active)
            compare(popup.text, "Deleted")
            tryCompare(popup, "active", false, 6000)
            compare(called, 1)
            compare(root.log, ["triggered"])
        }

        function test_default_timeout() {
            popup.execute("x")
            compare(popup._timeout, 4000)
            popup.cancel()
        }

        function test_tap_cancels() {
            var called = 0
            popup.execute("Cleared", function() { called++ }, 5000)
            tryCompare(popup, "opacity", 1.0)
            // Wait for the popup to slide in before tapping it.
            tryVerify(function() { return popup.y >= 0 && popup.pending && popup._contentOpacity === 1 })
            mouseClick(popup)
            verify(!popup.active)
            compare(root.log, ["canceled"])
            // The countdown is stopped, so the action can no longer run.
            verify(!popup.pending)
            compare(called, 0)
        }

        function test_trigger_now() {
            var called = 0
            popup.execute("", function() { called++ }, 5000)
            popup.trigger()
            compare(called, 1)
            compare(root.log, ["triggered"])
        }

        function test_list_item_remorse() {
            var called = 0
            var r = listItem.remorseAction("Deleting", function() { called++ }, 100)
            verify(r.pending)
            tryCompare(r, "pending", false, 6000)
            // After the countdown the item swipes away (or shows the
            // first-time swipe hint) and then runs the action.
            tryVerify(function() { return called === 1 }, 6000)
        }

        function test_singleton() {
            var called = 0
            var p = Remorse.popupAction(page, "Deleted", function() { called++ }, 100)
            verify(p.active)
            tryCompare(p, "active", false, 6000)
            compare(called, 1)
        }
    }
}
