// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PullDownMenu / PushUpMenu (Silica's BSD QML on Keel's PulleyMenuLogic):
// activation by dragging past the content end, the item at the activation
// point selected on release, locking open when pulled past the items, taps
// on a locked menu, earlyClick/clicked/delayedClick order, close(). Real
// pointer gestures only; no internals are driven.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    id: root
    width: 540
    height: 960
    property var log: []

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            id: pullMenu
            MenuItem {
                id: topItem
                text: "Top"
                onEarlyClick: root.log.push("top:early")
                onClicked: root.log.push("top:clicked")
                onDelayedClick: root.log.push("top:delayed")
            }
            MenuItem {
                id: bottomItem
                text: "Bottom"
                onClicked: root.log.push("bottom:clicked")
            }
        }
        PushUpMenu {
            id: pushMenu
            MenuItem { id: pushItem; text: "More"; onClicked: root.log.push("push:clicked") }
        }
        Column {
            id: column
            width: parent.width
            Repeater {
                model: 5
                Label { text: "row " + index; height: Theme.itemSizeSmall }
            }
        }
    }

    TestCase {
        name: "Pulley"
        when: windowShown

        function init() {
            pullMenu.close(true)
            pushMenu.close(true)
            flick.contentY = flick.originY
            root.log = []
            tryVerify(function() { return !pullMenu.active && !pushMenu.active })
        }

        function test_wiring() {
            compare(flick.pullDownMenu, pullMenu)
            compare(flick.pushUpMenu, pushMenu)
            compare(pullMenu.topMargin, Theme.itemSizeSmall)
            compare(pullMenu.spacing, 0)
            verify(!pullMenu.active)
            verify(pullMenu._activeHeight > topItem.height + bottomItem.height)
            // Items in a pulley menu use the menu's item height.
            compare(topItem.height, pullMenu._menuItemHeight)
        }

        // Drags the flickable by `distance` (positive: down) and leaves the
        // pointer pressed; returns the end point.
        function drag(distance) {
            var x = root.width / 2
            var y = distance > 0 ? 100 : root.height - 100
            mousePress(flick, x, y)
            var steps = 30
            for (var i = 1; i <= steps; ++i)
                mouseMove(flick, x, y + distance * i / steps, 10)
            return Qt.point(x, y + distance)
        }

        // How far the content has to be pulled for the menu item to sit at
        // the activation point (Silica's PulleyMenuBase: the item under the
        // menu content position, one item height in from the content).
        function pullFor(item) {
            return pullMenu._effectiveTopMargin + pullMenu._contentColumn.height
                    - item.mapToItem(pullMenu._contentColumn, 0, 0).y - item.height / 2
                    + pullMenu._menuItemHeight / 2
        }

        // Flickable damps a drag past its bounds until the menu is active;
        // drag in steps until the content has moved `pull` pixels.
        function pullTo(pull) {
            var x = root.width / 2
            var y = 100
            mousePress(flick, x, y)
            for (var i = 1; i < 400 && (flick.originY - flick.contentY) < pull; ++i) {
                y += 2
                mouseMove(flick, x, y, 5)
            }
            return Qt.point(x, y)
        }

        function test_drag_activates_and_highlights() {
            var p = pullTo(pullFor(bottomItem))
            verify(pullMenu.active, "dragging past the top activates the menu")
            compare(pullMenu.menuItem, bottomItem)
            mouseRelease(flick, p.x, p.y)
            tryCompare(root, "log", ["bottom:clicked"])
            tryCompare(pullMenu, "active", false)
            tryCompare(flick, "contentY", flick.originY)
        }

        function test_click_order_and_bounce_back() {
            var p = pullTo(pullFor(topItem))
            compare(pullMenu.menuItem, topItem)
            mouseRelease(flick, p.x, p.y)
            tryCompare(root, "log", ["top:early", "top:clicked", "top:delayed"])
            tryCompare(flick, "contentY", flick.originY)
            verify(!pullMenu.active)
        }

        function test_lock_open_and_tap() {
            var p = pullTo(pullMenu._activeHeight + Theme.itemSizeSmall)
            mouseRelease(flick, p.x, p.y)
            // Pulled past the last item: the menu stays open at its final position.
            tryCompare(flick, "contentY", pullMenu._finalPosition)
            verify(pullMenu.active)
            compare(root.log, [])
            // A tap on a locked menu clicks at once (no earlyClick, as in Silica).
            mouseClick(topItem)
            tryCompare(root, "log", ["top:clicked", "top:delayed"])
            tryCompare(pullMenu, "active", false)
            tryCompare(flick, "contentY", flick.originY)
        }

        function test_short_drag_does_nothing() {
            var p = pullTo(Theme.paddingSmall)
            mouseRelease(flick, p.x, p.y)
            tryCompare(flick, "contentY", flick.originY)
            tryCompare(pullMenu, "active", false)
            compare(root.log, [])
        }

        function test_push_up_menu() {
            var x = root.width / 2
            var y = root.height - 100
            mousePress(flick, x, y)
            var rest = flick.originY + Math.max(flick.contentHeight, flick.height) - flick.height
            for (var i = 1; i < 400 && flick.contentY - rest < pushMenu._contentEnd + pushMenu._menuItemHeight / 2; ++i) {
                y -= 2
                mouseMove(flick, x, y, 5)
            }
            verify(pushMenu.active)
            compare(pushMenu.menuItem, pushItem)
            mouseRelease(flick, x, y)
            tryCompare(root, "log", ["push:clicked"])
            tryCompare(pushMenu, "active", false)
        }

        function test_busy_and_close() {
            pullMenu.busy = true
            var p = pullTo(pullMenu._activeHeight + Theme.itemSizeSmall)
            mouseRelease(flick, p.x, p.y)
            tryCompare(flick, "contentY", pullMenu._finalPosition)
            verify(pullMenu.active)
            pullMenu.close()
            tryCompare(pullMenu, "active", false)
            tryCompare(flick, "contentY", flick.originY)
            pullMenu.busy = false
        }
    }
}
