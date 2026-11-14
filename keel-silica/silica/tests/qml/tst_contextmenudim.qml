// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// An open ContextMenu dims the window around its list item, never the item
// and the menu themselves. With shaders the item is lifted out of the dimmed
// window (Silica's removeOpacityEffect); on the software scene graph, which
// these tests run on, the window above and below the item is shaded.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    width: 540
    height: 960
    // As in an app's main.qml, where the ApplicationWindow is the root.
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component {
            Page {
                SilicaListView {
                    objectName: "list"
                    anchors.fill: parent
                    model: 6
                    delegate: ListItem {
                        objectName: "row" + index
                        contentHeight: Theme.itemSizeMedium
                        Rectangle { anchors.fill: parent; color: "white" }
                        menu: ContextMenu { MenuItem { text: "Copy" } MenuItem { text: "Delete" } }
                    }
                }
            }
        }
    }

    TestCase {
        name: "ContextMenuDim"
        when: windowShown

        function find(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; ++i) {
                var r = find(kids[i], name)
                if (r)
                    return r
            }
            if (item.contentItem && item.contentItem !== item)
                return find(item.contentItem, name)
            return null
        }

        function test_itemAndMenuStayBright() {
            tryVerify(function() { return win.pageStack.currentPage && !win.pageStack.busy })
            var row = null
            tryVerify(function() { row = find(win.pageStack.currentPage, "row1"); return row !== null })
            var other = find(win.pageStack.currentPage, "row4")
            row.openMenu()
            tryVerify(function() { return row.menuOpen && !row._menuItem._displayHeightAnimating })
            wait(400)
            var img = grabImage(win)
            var inItem = row.mapToItem(win, row.width / 2, Theme.itemSizeMedium / 2)
            var inMenu = row.mapToItem(win, row.width / 2, Theme.itemSizeMedium + 10)
            var outside = other.mapToItem(win, other.width / 2, other.height / 2)
            // The item's white is untouched; the menu is drawn at full
            // opacity; another row is dimmed (no longer white).
            verify(Qt.colorEqual(img.pixel(inItem.x, inItem.y), "white"))
            verify(img.pixel(inMenu.x, inMenu.y).a > 0.99)
            verify(!Qt.colorEqual(img.pixel(outside.x, outside.y), "white"))
            verify(img.pixel(outside.x, outside.y).r < 0.6)
            row.closeMenu()
            tryVerify(function() { return !row.menuOpen })
            wait(500)
            img = grabImage(win)
            outside = other.mapToItem(win, other.width / 2, other.height / 2)
            verify(Qt.colorEqual(img.pixel(outside.x, outside.y), "white"))
        }
    }
}
