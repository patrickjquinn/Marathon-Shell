// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Types that Keel gained by porting Silica's BSD QML (keel/silica/PROVENANCE.md):
// each instantiates in a page without warnings, and the dialogs open and
// close on the page stack.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private

Item {
    id: root
    width: 540
    height: 960
    // As in an app's main.qml, where the ApplicationWindow is the root.
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        cover: null
        initialPage: Component { Page { objectName: "first" } }
    }

    Component {
        id: content
        Page {
            property alias column: col
            property alias grid: grid
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: col.height
                Column {
                    id: col
                    width: parent.width
                    ColorPicker { objectName: "colorPicker" }
                    ColumnView {
                        objectName: "columnView"
                        width: parent.width
                        itemHeight: Theme.itemSizeSmall
                        model: 3
                        delegate: Label { text: "row " + index }
                    }
                    DatePicker { objectName: "datePicker"; date: new Date(2026, 9, 1, 12, 0, 0) }
                    ExpandingSectionGroup {
                        ExpandingSection {
                            objectName: "section"
                            title: "Section"
                            content.sourceComponent: Label { text: "inside" }
                        }
                    }
                    FirstTimeUseCounter { key: "/keel/tests/ported/hint"; limit: 2 }
                    Keypad { objectName: "keypad" }
                    TapInteractionHint { }
                    IconComboBox {
                        label: "Icons"
                        menu: ContextMenu { IconMenuItem { text: "Add"; icon.source: "image://theme/icon-m-add" } }
                    }
                    MiniComboBox { label: "Mini"; menu: ContextMenu { MenuItem { text: "One" } } }
                    SecondaryButton { text: "Secondary" }
                    HighlightBar { }
                    TextEditor { }
                }
                SilicaGridView {
                    id: grid
                    y: col.height
                    width: 540
                    height: 270
                    model: 4
                    cellWidth: 135
                    cellHeight: 135
                    delegate: GridItem { Label { text: index } }
                }
            }
        }
    }

    Component { id: colorDialog; ColorPickerDialog { } }
    Component { id: colorPage; ColorPickerPage { } }
    Component { id: dateDialog; DatePickerDialog { date: new Date(2026, 9, 1, 12, 0, 0) } }
    Component { id: timeDialog; TimePickerDialog { hour: 13; minute: 30 } }

    TestCase {
        name: "Ported"
        when: windowShown

        property bool savedImmediate
        function initTestCase() { savedImmediate = Private.Config._keelImmediatePageTransitions }
        function cleanupTestCase() { Private.Config._keelImmediatePageTransitions = savedImmediate }

        function init() {
            Private.Config._keelImmediatePageTransitions = true
            while (win.pageStack.depth > 1)
                win.pageStack.pop(undefined, PageStackAction.Immediate)
            // Any warning fails, except Qt 6.10+'s note that Silica's
            // `palette` shadows Item.palette: that is Silica's API, and the
            // `override` keyword it suggests does not parse on Qt 6.4-6.9.
            failOnWarning(/^(?!Member palette of the object \S+ overrides a member of the base object)/)
        }

        function test_types_instantiate() {
            var page = win.pageStack.push(content)
            verify(page !== null)
            wait(50)
            verify(findChild(page, "colorPicker") !== null)
            compare(findChild(page, "datePicker").year, 2026)
            compare(findChild(page, "datePicker").month, 10)
            compare(page.grid.count, 4)
        }

        function test_dialogs_open_and_close() {
            var dialogs = [colorDialog, colorPage, dateDialog, timeDialog]
            for (var i = 0; i < dialogs.length; ++i) {
                var d = win.pageStack.push(dialogs[i])
                verify(d !== null, "dialog " + i)
                compare(win.pageStack.currentPage, d)
                compare(d.status, PageStatus.Active)
                win.pageStack.pop()
                compare(win.pageStack.depth, 1)
            }
        }

        // Silica's OverlayGradient reads palette.overlayBackgroundColor: Keel's
        // OverlayGradientBase must carry Silica's palette, not Qt Quick's.
        function test_overlay_gradient_colors() {
            var g = Qt.createQmlObject("import Sailfish.Silica.private 1.0; OverlayGradient { }", root)
            verify(Qt.colorEqual(g.palette.overlayBackgroundColor, Theme.overlayBackgroundColor))
            verify(g.startColor.a > 0)
            compare(g.endColor.a, 0)
            g.destroy()
        }

        function test_time_picker_dialog_value() {
            var d = win.pageStack.push(timeDialog)
            compare(d.hour, 13)
            compare(d.minute, 30)
            d.accept()
            tryCompare(win.pageStack, "depth", 1)
        }
    }
}
