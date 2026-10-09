// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PagedView and Palette (Sailfish.Silica's public types): pages from a
// model with the documented attached properties, moveTo() with and without
// a transition, changing currentIndex, drags to the next and previous page
// (with wrapping and without), the page cache, itemAt() and exposedItems,
// directions and alignment;
// an app's own Palette.
import QtQuick
import QtQml.Models
import QtTest
import Sailfish.Silica

Item {
    id: root
    width: 400
    height: 600

    property var made: []

    Component {
        id: pagedView
        PagedView {
            width: 400
            height: 600
            model: 6
            delegate: Rectangle {
                id: page
                property int pageIndex: index
                readonly property bool current: PagedView.isCurrentItem
                readonly property bool shown: PagedView.exposed
                readonly property Item owner: PagedView.view
                width: PagedView.contentWidth
                height: PagedView.contentHeight / 2
                color: "gray"
                Component.onCompleted: root.made.push(index)
                MouseArea {
                    id: clicker
                    property int clicks
                    anchors.fill: parent
                    onClicked: clicks++
                }
                property alias clicks: clicker.clicks
            }
        }
    }

    // As jolla-camera's switcher: an ObjectModel of two full-size items, the
    // second current, one with its own `visible` binding.
    Component {
        id: objectPagedView
        PagedView {
            id: ov
            width: 400
            height: 600
            wrapMode: PagedView.NoWrap
            currentIndex: 1
            property bool showFirst: true
            // What a currentItem handler sees (the switcher reads it there).
            property bool currentAtChange
            onCurrentItemChanged: currentAtChange = currentItem ? currentItem.current : false
            model: ObjectModel {
                Rectangle {
                    objectName: "first"
                    width: 400; height: 600; color: "red"
                    visible: ov.showFirst
                    readonly property bool current: PagedView.isCurrentItem
                }
                Rectangle {
                    objectName: "second"
                    width: 400; height: 600; color: "blue"
                    readonly property bool current: PagedView.isCurrentItem
                }
            }
        }
    }

    // As jolla-camera: the camera roll (a NoWrap PagedView, newest first,
    // older photos to the left) inside the switcher's first page.
    Component {
        id: nestedPagedView
        PagedView {
            id: outerView
            width: 400
            height: 600
            wrapMode: PagedView.NoWrap
            currentIndex: 0
            property alias roll: rollView
            model: ObjectModel {
                Item {
                    width: 400; height: 600
                    PagedView {
                        id: rollView
                        anchors.fill: parent
                        model: 3
                        direction: PagedView.RightToLeft
                        wrapMode: PagedView.NoWrap
                        delegate: Rectangle { width: 400; height: 600; color: "gray" }
                    }
                }
                Rectangle { width: 400; height: 600; color: "blue" }
            }
        }
    }

    ListModel { id: growing }
    ListModel { id: shrinking }
    Component {
        id: growingPagedView
        PagedView {
            width: 400
            height: 600
            model: growing
            direction: PagedView.RightToLeft
            wrapMode: PagedView.NoWrap
            delegate: Rectangle { width: 400; height: 600; color: "gray" }
        }
    }

    Component {
        id: plainPalette
        Item {
            property Palette own: Palette { highlightColor: "#ff0000" }
            SilicaItem { id: silica }
            property alias silica: silica
        }
    }

    TestCase {
        name: "PagedView"
        when: windowShown

        function init() { root.made = [] }

        function create(props) {
            var v = createTemporaryObject(pagedView, root, props || {})
            verify(v)
            tryVerify(function() { return v.currentItem !== null })
            return v
        }

        function test_pages_and_attached() {
            var v = create()
            compare(v.count, 6)
            compare(v.currentIndex, 0)
            var page = v.currentItem
            compare(page.pageIndex, 0)
            verify(page.current)
            verify(page.shown)
            compare(page.owner, v)
            compare(page.width, 400)
            compare(page.height, 300)
            // Centred along the other axis.
            compare(page.y, 150)
            compare(page.x, 0)
            // The cache: the current page and two either side (wrapping).
            compare(root.made.sort(), [0, 1, 2, 4, 5])
            compare(v.contentItem.width, 400)
        }

        // Silica's itemAt() and exposedItems, which its TabButton reads.
        function test_item_at_and_exposed_items() {
            var v = create()
            compare(v.itemAt(0), v.currentItem)
            compare(v.itemAt(1).pageIndex, 1)
            compare(v.itemAt(3), null, "outside the cache")
            compare(v.exposedItems.length, 1)
            compare(v.exposedItems[0], v.currentItem)
            v.moveTo(2, PagedView.Immediate)
            compare(v.itemAt(2), v.currentItem)
            compare(v.exposedItems[0].pageIndex, 2)
        }

        function test_move_to() {
            var v = create()
            v.moveTo(3, PagedView.Immediate)
            compare(v.currentIndex, 3)
            compare(v.currentItem.pageIndex, 3)
            compare(v.currentItem.x, 0)
            verify(!v.moving)
            v.moveTo(4, PagedView.Animated)
            compare(v.currentIndex, 4)
            verify(v.moving)
            tryCompare(v, "moving", false)
            compare(v.currentItem.x, 0)
            verify(v.currentItem.current)
            // Writing currentIndex animates too.
            v.currentIndex = 2
            verify(v.moving)
            tryCompare(v, "moving", false)
            compare(v.currentItem.pageIndex, 2)
            v.moveTo(99, PagedView.Immediate)
            compare(v.currentIndex, 2)
        }

        function test_drag_to_next_and_previous() {
            var v = create()
            mouseDrag(v, 300, 300, -250, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 1)
            mouseDrag(v, 100, 300, 250, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 0)
            // Wrap (the default): before the first is the last.
            mouseDrag(v, 100, 300, 250, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 5)
            // A short drag springs back.
            mouseDrag(v, 200, 300, -30, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 5)
            compare(v.currentItem.x, 0)
            // A tap still reaches the page.
            mouseClick(v, 200, 300)
            compare(v.currentItem.clicks, 1)
        }

        function test_no_wrap() {
            var v = create({ "wrapMode": PagedView.NoWrap })
            compare(root.made.sort(), [0, 1, 2])
            mouseDrag(v, 100, 300, 250, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 0)
            v.moveTo(5, PagedView.Immediate)
            mouseDrag(v, 300, 300, -250, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 5)
        }

        function test_right_to_left_and_vertical() {
            var v = create({ "direction": PagedView.RightToLeft })
            // The next page comes from the left.
            mouseDrag(v, 100, 300, 250, 0)
            tryCompare(v, "moving", false)
            compare(v.currentIndex, 1)
            var w = create({ "direction": PagedView.TopToBottom, "verticalAlignment": PagedView.AlignTop })
            compare(w.currentItem.y, 0)
            mouseDrag(w, 200, 500, 0, -300)
            tryCompare(w, "moving", false)
            compare(w.currentIndex, 1)
            verify(w.interactive)
            w.interactive = false
            mouseDrag(w, 200, 500, 0, -300)
            wait(50)
            compare(w.currentIndex, 1)
        }

        function test_nested_drag_hands_on_at_the_end() {
            var v = createTemporaryObject(nestedPagedView, root)
            verify(v)
            tryVerify(function() { return v.currentItem !== null && v.roll.currentItem !== null })
            // Older photos: the roll moves, the switcher stays.
            mouseDrag(v, 100, 300, 250, 0)
            tryCompare(v.roll, "moving", false)
            compare(v.roll.currentIndex, 1)
            compare(v.currentIndex, 0)
            // Back to the newest, then past it: the switcher moves on.
            mouseDrag(v, 300, 300, -250, 0)
            tryCompare(v.roll, "moving", false)
            compare(v.roll.currentIndex, 0)
            var sawMoving = false
            v.movingChanged.connect(function() { if (v.moving) sawMoving = true })
            mouseDrag(v, 300, 300, -250, 0)
            tryCompare(v, "moving", false)
            verify(sawMoving)
            compare(v.currentIndex, 1)
            compare(v.roll.currentIndex, 0)
        }

        function test_nested_drag_without_a_page_for_either() {
            var v = createTemporaryObject(nestedPagedView, root)
            tryVerify(function() { return v.currentItem !== null && v.roll.currentItem !== null })
            v.roll.moveTo(2, PagedView.Immediate)
            // The oldest photo, dragged further: neither has a page there.
            mouseDrag(v, 100, 300, 250, 0)
            tryCompare(v.roll, "moving", false)
            tryCompare(v, "moving", false)
            compare(v.roll.currentIndex, 2)
            compare(v.currentIndex, 0)
        }

        function test_cache_size() {
            var v = create({ "cacheSize": 0, "wrapMode": PagedView.NoWrap })
            compare(root.made, [0])
            v.moveTo(2, PagedView.Immediate)
            compare(root.made, [0, 2])
        }

        function test_palette() {
            var item = createTemporaryObject(plainPalette, root)
            compare(String(item.own.highlightColor), "#ff0000")
            verify(item.own.secondaryHighlightColor !== Theme.secondaryHighlightColor)
            compare(String(item.silica.palette.primaryColor), String(Theme.primaryColor))
            item.silica.palette.highlightColor = "#00ff00"
            compare(String(item.silica.palette.highlightColor), "#00ff00")
        }

        function test_objectModel() {
            var v = createTemporaryObject(objectPagedView, root)
            verify(v)
            compare(v.count, 2)
            var first = v.model.get(0), second = v.model.get(1)
            tryCompare(v, "currentItem", second)
            verify(second.current)
            verify(v.currentAtChange)
            verify(!first.current)
            // The current item is in view, the other beside it.
            compare(second.mapToItem(v, 0, 0).x, 0)
            compare(first.mapToItem(v, 0, 0).x, -400)
            // The app's own visible binding is kept.
            v.showFirst = false
            verify(!first.visible)
            v.showFirst = true
            verify(first.visible)
            v.moveTo(0, PagedView.Immediate)
            compare(v.currentItem, first)
            verify(first.current)
            verify(v.currentAtChange)
            compare(first.mapToItem(v, 0, 0).x, 0)
            compare(second.mapToItem(v, 0, 0).x, 400)
        }

        // A model that grows while shown (the camera roll): no binding loop
        // on count, and the pages follow.
        // Deleting the page on show, as the camera's roll does: the view
        // releases its pages after the model is done, so Qt 6 does not crash
        // in DelegateModel, and the next page shows.
        function test_removing_the_current_page() {
            shrinking.clear()
            for (var i = 0; i < 4; ++i)
                shrinking.append({ n: i })
            var v = createTemporaryObject(growingPagedView, root, { model: shrinking })
            compare(v.count, 4)
            shrinking.remove(v.currentIndex)
            wait(50)
            compare(v.count, 3)
            verify(v.currentItem !== null)
            shrinking.remove(v.currentIndex)
            shrinking.remove(v.currentIndex)
            wait(50)
            compare(v.count, 1)
            verify(v.currentItem !== null)
            verify(v.currentItem.visible)
        }

        function test_growingModel() {
            failOnWarning(/Binding loop/)
            growing.clear()
            var v = createTemporaryObject(growingPagedView, root)
            compare(v.count, 0)
            growing.append({ n: 1 })
            growing.append({ n: 2 })
            growing.insert(0, { n: 0 })
            compare(v.count, 3)
            verify(v.currentItem !== null)
        }
    }
}
