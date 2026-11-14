// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The ApplicationWindow's own children share one item with the page stack,
// as in Silica: a child with a negative z (a camera's VideoOutput) is drawn
// under the pages, a child with the default z over them.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    width: 540
    height: 960

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { objectName: "page" } }

        Rectangle { id: under; objectName: "under"; z: -1; anchors.fill: parent; color: "red" }
        Rectangle { id: over; objectName: "over"; width: 10; height: 10; color: "blue" }
    }

    TestCase {
        name: "WindowLayering"
        when: windowShown

        function indexIn(item, parentItem) {
            var kids = parentItem.children
            for (var i = 0; i < kids.length; ++i)
                if (kids[i] === item)
                    return i
            return -1
        }

        function test_childrenShareTheStackItem() {
            tryVerify(function() { return win.pageStack.currentPage !== null && !win.pageStack.busy })
            compare(under.parent, win.pageStack.parent)
            compare(over.parent, win.pageStack.parent)
            compare(win.contentItem, win.pageStack.parent)
        }

        function test_negativeZIsUnderThePages() {
            tryVerify(function() { return win.pageStack.currentPage !== null })
            var p = win.pageStack.parent
            verify(indexIn(win.pageStack, p) >= 0)
            // Stacking order among siblings: z first, then child order.
            verify(under.z < win.pageStack.z)
            verify(over.z >= win.pageStack.z && indexIn(over, p) > indexIn(win.pageStack, p))
            // What a pixel shows: the page (transparent) over the red child,
            // so the red shows through where no page item draws.
            var img = grabImage(win)
            verify(Qt.colorEqual(img.pixel(270, 480), "red"))
            verify(Qt.colorEqual(img.pixel(5, 5), "blue"))
        }
    }
}
