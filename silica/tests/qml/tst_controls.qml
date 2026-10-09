// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Buttons, switches, slider, list items and context menus, covers,
// placeholders and decorators.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    id: root
    width: 540
    height: 1400
    property var log: []

    Column {
        id: column
        width: parent.width
        Button { id: button; text: "Go"; onClicked: root.log.push("button") }
        IconButton { id: iconButton; icon.source: "image://theme/icon-m-add"; onClicked: root.log.push("icon") }
        TextSwitch {
            id: textSwitch
            text: "Wi-Fi"
            description: "Wireless"
            onClicked: root.log.push("switch:" + checked)
        }
        Switch { id: plainSwitch; onClicked: root.log.push("plain:" + checked) }
        Slider {
            id: slider
            // Silica's Slider has no default width.
            width: parent.width
            minimumValue: 0; maximumValue: 10; stepSize: 1; value: 5
            label: "Volume"; valueText: value
        }
        SectionHeader { id: section; text: "Section" }
        DetailItem { id: detail; label: "Size"; value: "12 MB" }
        Separator { id: separator; width: parent.width }
        ListItem {
            id: listItem
            contentHeight: Theme.itemSizeSmall
            Label { text: "Row" }
            onClicked: root.log.push("row")
            menu: ContextMenu {
                id: listMenu
                MenuItem { id: editItem; text: "Edit"; onClicked: root.log.push("edit") }
                MenuItem { text: "Delete" }
            }
        }
        Label { id: after; text: "after" }
        BusyIndicator { id: busy; running: true; size: BusyIndicatorSize.Small }
    }

    SilicaListView {
        id: emptyView
        y: 1050
        width: parent.width
        height: 300
        model: 0
        ViewPlaceholder { id: placeholder; enabled: emptyView.count === 0; text: "Nothing"; hintText: "Pull down" }
        VerticalScrollDecorator { id: decorator }
    }

    CoverBackground {
        id: cover
        visible: false
        Label { text: "cover" }
        CoverActionList {
            id: actions
            CoverAction { id: action1; iconSource: "image://theme/icon-cover-next"; onTriggered: root.log.push("cover1") }
            CoverAction { iconSource: "image://theme/icon-cover-pause"; onTriggered: root.log.push("cover2") }
        }
    }

    TestCase {
        name: "Controls"
        when: windowShown

        function init() { root.log = [] }

        // Waits until a menu item is fully shown in its open menu.
        function waitForMenuItem(menu, item) {
            tryVerify(function() {
                var bottom = menu.mapToItem(null, 0, menu.height).y
                return item.visible && item.mapToItem(null, 0, item.height).y <= bottom + 0.5
            })
            // Menu items take taps once the opening animation has finished.
            tryVerify(function() { return menu._expanded && !menu._displayHeightAnimating })
        }

        function test_button() {
            verify(button.width >= Theme.buttonWidthSmall)
            mouseClick(button)
            compare(root.log, ["button"])
            mousePress(button)
            verify(button.down)
            mouseRelease(button)
        }

        function test_icon_button() {
            mouseClick(iconButton)
            compare(root.log, ["icon"])
            compare(iconButton.icon.source.toString(), "image://theme/icon-m-add")
        }

        function test_text_switch() {
            verify(!textSwitch.checked)
            mouseClick(textSwitch)
            verify(textSwitch.checked)
            compare(root.log, ["switch:true"])
            textSwitch.automaticCheck = false
            mouseClick(textSwitch)
            verify(textSwitch.checked)
            textSwitch.automaticCheck = true
        }

        function test_switch_handler_order() {
            mouseClick(plainSwitch)
            // The app's onClicked runs as well as the built-in toggle.
            verify(plainSwitch.checked)
            compare(root.log, ["plain:true"])
        }

        function test_slider() {
            compare(slider.value, 5)
            compare(slider.sliderValue, 5)
            var trackX = slider.leftMargin
            var trackW = slider.width - slider.leftMargin - slider.rightMargin
            var y = slider.height / 2
            waitForRendering(slider)
            // A tap moves the handle and sets the value on release.
            mouseClick(slider, trackX + trackW * 0.8, y)
            compare(slider.value, 8)
            // A drag updates the value as the handle moves (the handle starts
            // following once the drag threshold is passed, so it lags the
            // pointer by that much).
            mousePress(slider, trackX + trackW * 0.8, y)
            for (var i = 1; i <= 10; ++i)
                mouseMove(slider, trackX + trackW * (0.8 - 0.05 * i), y, 10)
            verify(slider.value >= 3 && slider.value <= 4, "value follows the drag: " + slider.value)
            var dragged = slider.value
            mouseRelease(slider, trackX + trackW * 0.3, y)
            compare(slider.value, dragged)
            slider.value = 20
            compare(slider.sliderValue, 10)
        }

        function test_labels() {
            compare(section.horizontalAlignment, Text.AlignRight)
            verify(Qt.colorEqual(section.color, Theme.highlightColor))
            compare(detail.label, "Size")
            compare(detail.value, "12 MB")
            compare(separator.height, 2)
        }

        function test_list_item_menu() {
            var y0 = after.y
            mousePress(listItem)
            tryVerify(function() { return listItem.menuOpen }, 3000)
            mouseRelease(listItem)
            verify(listItem.highlighted)
            tryVerify(function() { return after.y > y0 })
            waitForMenuItem(listMenu, editItem)
            mouseClick(editItem)
            tryCompare(root, "log", ["edit"])
            tryCompare(listItem, "menuOpen", false)
            tryCompare(listItem, "height", Theme.itemSizeSmall)
            mouseClick(listItem)
            compare(root.log, ["edit", "row"])
        }

        function test_busy_indicator() {
            verify(busy.running)
            compare(busy.width, Theme.iconSizeSmall)
            busy.running = false
            // Fades out (Silica keeps the item visible at opacity 0).
            tryCompare(busy, "opacity", 0)
        }

        function test_placeholder_and_decorator() {
            verify(placeholder.enabled)
            compare(placeholder.flickable, emptyView)
            tryCompare(placeholder, "opacity", 1.0)
            compare(decorator.flickable, emptyView)
            compare(decorator.parent, emptyView)
        }

        function test_cover_actions() {
            compare(cover.transparent, true)
            compare(cover.status, Cover.Inactive)
            compare(cover._actions.length, 2)
            action1.trigger()
            compare(root.log, ["cover1"])
            // Tapping the drawn action triggers it too.
            cover.visible = true
            var area = cover.coverActionArea
            mouseClick(area, area.width * 0.75, area.height / 2)
            compare(root.log, ["cover1", "cover2"])
            cover.visible = false
            actions.enabled = false
            compare(cover._actionList, null)
            actions.enabled = true
        }

        function test_enter_key_attached() {
            var item = Qt.createQmlObject("import QtQuick 2.0; import Sailfish.Silica 1.0; Item { EnterKey.text: 'Go'; EnterKey.highlighted: true }", root)
            var att = KeelEnterKeyHelper.attachedTo(item)
            compare(att.text, "Go")
            verify(att.highlighted)
            verify(att.enabled)
            item.destroy()
        }
    }
}
