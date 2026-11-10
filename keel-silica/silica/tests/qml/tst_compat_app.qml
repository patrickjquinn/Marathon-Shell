// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Compatibility test: loads compatapp/harbour-keelsample.qml, an app written
// the way Harbour apps are (separate page files resolving `pageStack` and ids
// from the main QML file, relative page URLs, pulley menus, list items with
// context menus and remorse, a dialog with EnterKey, a cover with actions),
// and drives it.
import QtQuick 2.0
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    id: root
    width: 540
    height: 960

    property var app: null

    TestCase {
        name: "CompatApp"
        when: windowShown

        function initTestCase() {
            var c = Qt.createComponent(Qt.resolvedUrl("compatapp/harbour-keelsample.qml"))
            compare(c.status, Component.Ready, c.errorString())
            root.app = c.createObject(root, { width: root.width, height: root.height })
            verify(root.app !== null)
        }

        function first() { return root.app.pageStack.currentPage }

        // Pulls the page's pulley menu with a real drag until `item` is the
        // highlighted menu item, then releases (selects it).
        function pullSelect(menu, item) {
            var flick = menu.flickable
            var x = flick.width / 2
            var y = 150
            mousePress(flick, x, y)
            for (var i = 0; i < 400 && menu.menuItem !== item; ++i) {
                y += 2
                mouseMove(flick, x, y, 5)
            }
            compare(menu.menuItem, item)
            mouseRelease(flick, x, y)
        }

        function init() {
            // Let the previous test's page transition finish.
            tryCompare(root.app.pageStack, "busy", false)
        }

        function test_1_first_page() {
            compare(first().objectName, "firstPage")
            compare(first().status, PageStatus.Active)
            tryCompare(first().listView, "count", 2)
            compare(root.app.orientation, Orientation.Portrait)
        }

        function test_2_pull_down_opens_about() {
            var menu = first().pullDownMenu
            var about = findChild(menu, "aboutItem")
            verify(about)
            pullSelect(menu, about)
            // The item is clicked after its highlight animation.
            tryVerify(function() { return root.app.pageStack.currentPage.objectName === "aboutPage" })
            tryCompare(root.app.pageStack, "busy", false)
            compare(root.app.pageStack.currentPage.objectName, "aboutPage")
            compare(root.app.pageStack.depth, 2)
            root.app.pageStack.pop()
            tryCompare(root.app.pageStack, "depth", 1)
        }

        function test_3_add_note_with_dialog() {
            var menu = first().pullDownMenu
            pullSelect(menu, findChild(menu, "addItem"))
            tryVerify(function() { return root.app.pageStack.currentPage.objectName === "addDialog" })
            tryCompare(root.app.pageStack, "busy", false)
            var dialog = root.app.pageStack.currentPage
            compare(dialog.objectName, "addDialog")
            verify(!dialog.canAccept)
            compare(dialog.priorityBox.value, "normal")
            dialog.titleField.forceActiveFocus()
            keyClick(Qt.Key_T)
            keyClick(Qt.Key_E)
            compare(dialog.noteTitle, "te")
            verify(dialog.canAccept)
            dialog.pinSwitch.checked = true
            // EnterKey accepts the dialog.
            keyClick(Qt.Key_Return)
            tryCompare(root.app.pageStack, "depth", 1)
            tryCompare(root.app.pageStack, "busy", false)
            tryCompare(first().listView, "count", 3)
            compare(root.app.lastAction, "added te")
            compare(root.app.notes.get(2).pinned, true)
        }

        function test_4_open_detail_from_list() {
            var lv = first().listView
            var item = findChild(lv, "note_0")
            verify(item)
            mouseClick(item)
            tryCompare(root.app.pageStack, "busy", false)
            compare(root.app.pageStack.currentPage.objectName, "detailPage")
            compare(root.app.pageStack.currentPage.note, "Buy milk")
            root.app.pageStack.navigateBack()
            tryCompare(root.app.pageStack, "depth", 1)
        }

        function test_5_context_menu_remorse_delete() {
            var lv = first().listView
            var item = findChild(lv, "note_1")
            var before = lv.count
            item.openMenu()
            tryVerify(function() { return item.menuOpen })
            var remove = findChild(item._menuItem, "removeItem")
            verify(remove)
            tryVerify(function() { return remove.visible && remove.height > 0 })
            tryVerify(function() { return item._menuItem._expanded && !item._menuItem._displayHeightAnimating })
            mouseClick(remove)
            tryCompare(lv, "count", before - 1, 3000)
        }

        function test_6_cover() {
            var cover = root.app._loadCover()
            verify(cover !== null)
            compare(cover.objectName, "cover")
            compare(cover.countLabel.text, String(root.app.notes.count))
            var before = root.app.notes.count
            cover._actions[0].trigger()
            compare(root.app.notes.count, before + 1)
            compare(cover.countLabel.text, String(before + 1))
        }

        function test_7_orientation() {
            // Pages change orientation through their orientation transition.
            root.app.deviceOrientation = Orientation.Landscape
            tryCompare(first(), "orientation", Orientation.Landscape)
            verify(first().isLandscape)
            root.app.deviceOrientation = Orientation.Portrait
            tryVerify(function() { return first().isPortrait })
        }
    }
}
