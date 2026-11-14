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
    }
}
