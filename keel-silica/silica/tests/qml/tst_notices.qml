// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Notice and Notices (Silica public documentation): notices show one at a
// time, in order, for their duration, as Silica's NoticeItem in the window's
// indicator layer, anchored as asked; dismiss() and a tap end them early.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    width: 540
    height: 960
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page {} }
    }

    Notice {
        id: declared
        text: "Declared notice"
        duration: 200
        anchor: Notice.Top | Notice.Left
    }

    TestCase {
        name: "Notices"
        when: windowShown

        function noticeItems() {
            var found = []
            var children = win.indicatorParentItem.children
            for (var i = 0; i < children.length; ++i) {
                if (children[i].visible && children[i].notice !== undefined && children[i].applicationWindow !== undefined)
                    found.push(children[i])
            }
            return found
        }

        function cleanup() {
            while (Notices._current)
                Notices._dismissCurrent()
            tryCompare(Notices, "_queue", [])
        }

        function test_values() {
            verify(Notice.Short < Notice.Long)
            compare(declared.anchor & Notice.Top, Notice.Top)
            compare(Notice.Center, 0)
        }

        function test_showQueueAndTimeout() {
            Notices.show("First", 150)
            Notices.show("Second", 150, Notice.Top)
            compare(noticeItems().length, 1)
            var item = noticeItems()[0]
            compare(item.notice.text, "First")
            // The default anchor is the bottom of the window, centred.
            verify(item.y > win.height / 2)
            verify(Math.abs(item.x + item.width / 2 - win.width / 2) < 2)
            verify(item.width > 0 && item.height >= Theme.itemSizeExtraSmall)
            // The second follows once the first's duration has passed.
            tryVerify(function() { var n = noticeItems(); return n.length === 1 && n[0].notice.text === "Second" }, 2000)
            verify(noticeItems()[0].y < win.height / 2)
            tryCompare(Notices, "_current", null, 2000)
            compare(noticeItems().length, 0)
        }

        function test_declaredNoticeAndDismiss() {
            declared.show()
            verify(declared._shown)
            var item = noticeItems()[0]
            compare(item.notice, declared)
            verify(item.x < win.width / 2 && item.y < win.height / 2)
            declared.dismiss()
            verify(!declared._shown)
            compare(noticeItems().length, 0)
            // A declared notice can be shown again; it is not destroyed.
            declared.show()
            verify(declared._shown)
        }

        function test_tapDismisses() {
            Notices.show("Tap me", 10000)
            var item = noticeItems()[0]
            mouseClick(item, item.width / 2, item.height / 2)
            compare(Notices._current, null)
            compare(noticeItems().length, 0)
        }

        function test_longTextFits() {
            Notices.show("A long notice text that is wider than the window by quite a margin, so it scrolls", 10000)
            var item = noticeItems()[0]
            verify(item.width <= win.width)
            verify(item.clip)
        }
    }
}
