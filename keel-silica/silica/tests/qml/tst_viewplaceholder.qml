// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// ViewPlaceholder: where Silica puts it, but never over the view's header
// (a page header with a search field, on a short or landscape screen).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

TestCase {
    id: testCase
    name: "ViewPlaceholder"
    when: windowShown
    width: 960
    height: 540

    // As in an app's main.qml, where the ApplicationWindow is the root.
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { } }
    }

    Component {
        id: listPage
        Page {
            property alias list: list
            property alias placeholder: placeholder
            property real headerHeight
            SilicaListView {
                id: list
                anchors.fill: parent
                model: 0
                header: Item { width: list.width; height: headerHeight }
                ViewPlaceholder {
                    id: placeholder
                    enabled: true
                    text: "No bookmarks"
                    hintText: "Bookmark a page from the page menu"
                }
            }
        }
    }

    function open(headerHeight) {
        var page = pageStack.push(listPage, { headerHeight: headerHeight }, PageStackAction.Immediate)
        tryCompare(page, "status", PageStatus.Active)
        waitForRendering(page)
        return page
    }

    function test_silicas_place_under_a_short_header() {
        var page = open(Theme.paddingLarge)
        var p = page.placeholder
        compare(p.y, page.list.originY + p._yBase)
        verify(p.y > page.list.headerItem.y + page.list.headerItem.height)
        pageStack.pop(null, PageStackAction.Immediate)
    }

    function test_below_a_tall_header() {
        // PageHeader and SearchField: taller than a third of a landscape
        // screen less half the placeholder.
        var page = open(Math.round(win.height / 3) + Theme.itemSizeMedium)
        var p = page.placeholder
        var header = page.list.headerItem
        verify(page.list.originY + p._yBase < header.y + header.height, "Silica's place overlaps the header")
        compare(p.y, header.y + header.height + Theme.paddingLarge)
        pageStack.pop(null, PageStackAction.Immediate)
    }
}
