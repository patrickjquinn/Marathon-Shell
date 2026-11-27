// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TextField / TextArea input, placeholder and label, validator, EnterKey.
import QtQuick 2.0
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    id: root
    width: 540
    height: 960
    property int enterCount: 0
    property int areaEnterCount: 0

    Column {
        width: parent.width
        TextField {
            id: field
            placeholderText: "Name"
            label: "Name"
            EnterKey.iconSource: "image://theme/icon-m-enter-next"
            EnterKey.onClicked: { root.enterCount++; second.focus = true }
        }
        TextField {
            id: second
            validator: IntValidator { bottom: 1; top: 99 }
            EnterKey.enabled: acceptableInput
            EnterKey.onClicked: root.enterCount += 10
        }
        PasswordField { id: password }
        TextArea {
            id: area
            label: "Notes"
            EnterKey.onClicked: root.areaEnterCount++
        }
    }

    // A binding that reads `text` of fields whose own `text` is bound to a
    // property set at creation (as a page pushed with properties) must see
    // every later change; it reads the second field only once the first
    // passes (short-circuit), as an app's "valid" property does.
    Component {
        id: formComponent
        Item {
            property string initial
            property alias first: f1
            property alias second: f2
            readonly property bool valid: f1.text.indexOf("@") > 0 && f2.text.length > 0
            TextField { id: f1; text: parent.initial }
            TextField { id: f2; y: f1.height; echoMode: TextInput.Password }
        }
    }

    TestCase {
        name: "TextInput"

        function test_text_bindings_follow_changes() {
            var form = createTemporaryObject(formComponent, root, { initial: "me@example.com" })
            verify(form !== null)
            compare(form.first.text, "me@example.com")
            verify(!form.valid)
            form.second.text = "secret"
            verify(form.valid)
            form.first.text = "nobody"
            verify(!form.valid)
        }
        when: windowShown

        function test_typing() {
            field.forceActiveFocus()
            verify(field._editor.activeFocus)
            verify(field.highlighted)
            keyClick(Qt.Key_H)
            keyClick(Qt.Key_I)
            compare(field.text, "hi")
            compare(field.cursorPosition, 2)
            field.selectAll()
            compare(field.selectedText, "hi")
            field.text = "Keel"
            compare(field._editor.text, "Keel")
        }

        function test_placeholder_and_label() {
            field.text = ""
            var r = field.positionToRectangle(0)
            verify(r.x >= field.textLeftMargin)
            compare(field.label, "Name")
            compare(field.placeholderText, "Name")
            verify(field.labelVisible)
        }

        function test_enter_key() {
            root.enterCount = 0
            field.forceActiveFocus()
            compare(KeelEnterKeyHelper.attachedTo(field).enterKeyType, Qt.EnterKeyNext)
            keyClick(Qt.Key_Return)
            compare(root.enterCount, 1)
            verify(second._editor.activeFocus)
            // Disabled until the validator accepts the input.
            compare(second.acceptableInput, false)
            keyClick(Qt.Key_Return)
            compare(root.enterCount, 1)
            keyClick(Qt.Key_4)
            keyClick(Qt.Key_2)
            compare(second.text, "42")
            verify(second.acceptableInput)
            keyClick(Qt.Key_Enter)
            compare(root.enterCount, 11)
        }

        function test_click_focuses() {
            second.focus = false
            field.focus = false
            mouseClick(second, second.width / 2, Theme.paddingMedium + 5)
            verify(second._editor.activeFocus)
        }

        function test_password() {
            compare(password.echoMode, TextInput.Password)
            password._usePasswordEchoMode = false
            compare(password.echoMode, TextInput.Normal)
        }

        function test_text_area() {
            area.forceActiveFocus()
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_B)
            compare(area.text, "a\nb")
            compare(root.areaEnterCount, 1)
            verify(area._editor.lineCount >= 2)
        }

        function test_clipboard_roundtrip() {
            field.text = "copy me"
            field.selectAll()
            field.copy()
            compare(Clipboard.text, "copy me")
            field.text = ""
            field.paste()
            compare(field.text, "copy me")
        }

        // A press held still, as a person holds a word.
        function longPress(item, x, y) {
            mousePress(item, x, y)
            wait(1000)
            mouseRelease(item, x, y)
        }

        // Within the first line of text.
        readonly property real textY: Theme.paddingMedium + 5

        function menuOf(item) {
            verify(item._editMenu !== null)
            return item._editMenu
        }

        // The menu lays its actions out before the next frame.
        function tap(menu, name) {
            const action = findChild(menu, name)
            tryVerify(() => !isPolishScheduled(action.parent))
            mouseClick(action)
        }

        function cleanup() {
            for (const item of [field, password, area]) {
                item.text = ""
                if (item._editMenu)
                    item._editMenu.close()
            }
        }

        function shown(menu, name) {
            const action = findChild(menu, name)
            return menu.visible && action.visible
        }

        function test_long_press_selects_a_word_and_copies_only_on_copy() {
            field.focus = false
            field.text = "hello world"
            Clipboard.text = "before"
            longPress(field, field.positionToRectangle(8).x, textY)
            verify(field._editor.activeFocus)
            compare(field.selectedText, "world")
            compare(Clipboard.text, "before")
            const menu = menuOf(field)
            verify(shown(menu, "selectAll"))
            verify(shown(menu, "cut"))
            verify(shown(menu, "copy"))
            verify(shown(menu, "paste"))
            tap(menu, "copy")
            compare(Clipboard.text, "world")
            verify(!menu.visible)
            compare(field.text, "hello world")
        }

        function test_long_press_in_a_focused_field() {
            field.text = "hello world"
            field.forceActiveFocus()
            field.cursorPosition = 0
            longPress(field, field.positionToRectangle(1).x, textY)
            compare(field.selectedText, "hello")
            const menu = menuOf(field)
            verify(menu.visible)
            tap(menu, "cut")
            compare(Clipboard.text, "hello")
            compare(field.text, " world")
            verify(!menu.visible)
        }

        function test_select_all_then_paste_over_it() {
            field.text = "old text"
            field.focus = false
            Clipboard.text = "new"
            longPress(field, field.positionToRectangle(1).x, textY)
            const menu = menuOf(field)
            tap(menu, "selectAll")
            compare(field.selectedText, "old text")
            verify(menu.visible)
            verify(!shown(menu, "selectAll"))
            tap(menu, "paste")
            compare(field.text, "new")
            verify(field._editor.activeFocus)
        }

        function test_empty_field_offers_paste() {
            field.text = ""
            field.forceActiveFocus()
            Clipboard.text = "pasted"
            longPress(field, field.width / 2, textY)
            const menu = menuOf(field)
            verify(shown(menu, "paste"))
            verify(!shown(menu, "copy"))
            verify(!shown(menu, "cut"))
            verify(!shown(menu, "selectAll"))
            tap(menu, "paste")
            compare(field.text, "pasted")
        }

        function test_password_offers_paste_only() {
            for (const hidden of [true, false]) {
                password._usePasswordEchoMode = hidden
                password.text = "secret"
                password.focus = false
                Clipboard.text = "hunter2"
                longPress(password, password.positionToRectangle(2).x, textY)
                const menu = menuOf(password)
                verify(shown(menu, "paste"))
                verify(!shown(menu, "copy"))
                verify(!shown(menu, "cut"))
                verify(!shown(menu, "selectAll"))
                tap(menu, "paste")
                verify(password.text.indexOf("hunter2") >= 0)
                compare(Clipboard.text, "hunter2")
            }
            password._usePasswordEchoMode = true
        }

        function test_menu_closes_on_a_press_elsewhere_and_on_typing() {
            field.text = "hello world"
            field.focus = false
            longPress(field, field.positionToRectangle(1).x, textY)
            const menu = menuOf(field)
            verify(menu.visible)
            mouseClick(area, area.width / 2, Theme.paddingMedium + 5)
            verify(!menu.visible)
            field.forceActiveFocus()
            longPress(field, field.positionToRectangle(1).x, textY)
            verify(menu.visible)
            keyClick(Qt.Key_X)
            verify(!menu.visible)
        }

        function test_text_area_long_press() {
            area.text = "first line"
            area.focus = false
            longPress(area, area.positionToRectangle(1).x, textY)
            compare(area.selectedText, "first")
            verify(shown(menuOf(area), "copy"))
        }
    }
}
