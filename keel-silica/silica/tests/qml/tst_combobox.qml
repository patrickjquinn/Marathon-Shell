// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ComboBox selection rules from the Silica ComboBox documentation, and the
// ContextMenu it opens.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    width: 540
    height: 960

    Column {
        width: parent.width
        ComboBox {
            id: combo
            label: "Brightness"
            menu: ContextMenu {
                MenuItem { text: "automatic" }
                MenuItem { id: manualItem; text: "manual" }
                MenuItem { id: disabledItem; text: "off"; enabled: false }
                MenuItem { text: "high" }
            }
        }
        ComboBox {
            id: preset
            label: "Preset"
            currentIndex: 0
            currentItem: presetHigh
            menu: ContextMenu {
                MenuItem { text: "low" }
                MenuItem { id: presetHigh; text: "high" }
            }
        }
        Label { id: below; text: "below" }
    }

    TestCase {
        name: "ComboBox"
        when: windowShown

        function init() {
            combo.currentIndex = 0
            combo.menu.close()
            tryCompare(combo.menu, "height", 0)
        }

        function test_defaults() {
            compare(combo.currentIndex, 0)
            compare(combo.value, "automatic")
            compare(combo.currentItem.text, "automatic")
        }

        function test_currentItem_precedence() {
            compare(preset.currentItem, presetHigh)
            compare(preset.currentIndex, 1)
            compare(preset.value, "high")
        }

        function test_set_index() {
            combo.currentIndex = 3
            compare(combo.value, "high")
            combo.currentIndex = 10
            compare(combo.currentIndex, -1)
            compare(combo.currentItem, null)
            compare(combo.value, "")
        }

        function test_set_item() {
            combo.currentItem = manualItem
            compare(combo.currentIndex, 1)
            compare(combo.value, "manual")
            combo.currentItem = disabledItem
            compare(combo.currentIndex, -1)
            compare(combo.currentItem, null)
        }

        function test_select_from_menu() {
            var spy = Qt.createQmlObject("import QtTest 1.0; SignalSpy { signalName: 'activated' }", combo)
            spy.target = combo.menu
            var y0 = below.y
            mouseClick(combo, combo.width / 2, combo.contentHeight / 2)
            tryVerify(function() { return combo.menu.active })
            // The menu opens inline and pushes the content below down, until
            // its items are fully shown.
            tryVerify(function() { return below.y > y0 })
            tryVerify(function() {
                var m = combo.menu.mapToItem(null, 0, 0).y + combo.menu.height
                return manualItem.mapToItem(null, 0, manualItem.height).y <= m + 0.5
                        && below.mapToItem(null, 0, 0).y >= m - 0.5
            })
            // Menu items take taps once the opening animation has finished.
            tryVerify(function() { return combo.menu._expanded && !combo.menu._displayHeightAnimating })
            mouseClick(manualItem)
            compare(spy.count, 1)
            compare(spy.signalArguments[0][0], 1)
            compare(combo.currentIndex, 1)
            compare(combo.value, "manual")
            tryVerify(function() { return !combo.menu.active })
            tryCompare(combo.menu, "height", 0)
        }
    }
}
