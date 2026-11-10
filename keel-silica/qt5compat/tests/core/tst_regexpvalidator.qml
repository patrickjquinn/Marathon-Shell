// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// RegExpValidator under a plain Qt 5 style `import QtQuick 2.0`, as the
// corpus apps (nextcloudnotes, bitsailor, harbour-lib) use it.
import QtQuick 2.0
import QtTest 1.0

Item {
    id: root
    property bool secure: true
    property var secureRe: /^https:\/\/.+$/
    property var plainRe: /^https?:\/\/.+$/

    TextInput { id: cvv; validator: RegExpValidator { regExp: /^[0-9]{3,4}$/ } }
    TextInput { id: url; validator: RegExpValidator { regExp: root.secure ? root.secureRe : root.plainRe } }
    TextInput { id: fromString; validator: RegExpValidator { regExp: "^[a-f]+$" } }
    TextInput { id: noRegExp; validator: RegExpValidator { } }
    TextInput { id: caseless; validator: RegExpValidator { regExp: /^[a-f]{6}$/i } }

    TestCase {
        name: "RegExpValidator"

        function test_literal() {
            cvv.text = "12"
            verify(!cvv.acceptableInput)
            cvv.text = "123"
            verify(cvv.acceptableInput)
            cvv.text = "12345"
            verify(!cvv.acceptableInput)
            compare(cvv.validator.regExp.source, "^[0-9]{3,4}$")
        }
        function test_binding() {
            url.text = "http://example.org"
            verify(!url.acceptableInput)
            root.secure = false
            url.text = ""
            url.text = "http://example.org"
            verify(url.acceptableInput)
            root.secure = true
        }
        function test_string() {
            fromString.text = "abc"
            verify(fromString.acceptableInput)
            fromString.text = "abz"
            verify(!fromString.acceptableInput)
        }
        function test_default_accepts_anything() {
            noRegExp.text = "anything at all"
            verify(noRegExp.acceptableInput)
        }
        function test_case_insensitive_flag() {
            caseless.text = "ABCdef"
            verify(caseless.acceptableInput)
        }
    }
}
