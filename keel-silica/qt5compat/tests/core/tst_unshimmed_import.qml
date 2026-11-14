// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Imports the shims do not cover are unchanged: QtQuick 2.15 and 6.x (Keel's
// own QML) get Qt Quick as is, without the Qt 5 names, and Qt Quick's own
// version check still applies to properties under QtQuick 2.x.
import QtQuick 2.15
import QtTest 1.0

Item {
    TestCase {
        name: "UnshimmedImport"

        function test_no_qt5_names_in_qtquick_2_15() {
            var c = Qt.createQmlObject('import QtQuick 2.15; Item { RegularExpressionValidator { } }', this)
            verify(c)
            var failed = false
            try {
                Qt.createQmlObject('import QtQuick 2.15; Item { RegExpValidator { } }', this)
            } catch (e) {
                failed = true
            }
            verify(failed)
        }
        function test_no_qt5_names_in_qtquick_6() {
            var failed = false
            try {
                Qt.createQmlObject('import QtQuick 6.0; ListView { model: VisualItemModel { } }', this)
            } catch (e) {
                failed = true
            }
            verify(failed)
        }
        function test_shim_import_in_older_minor() {
            for (var minor = 0; minor <= 14; ++minor) {
                var o = Qt.createQmlObject('import QtQuick 2.' + minor
                                           + '; Item { property var v: RegExpValidator { regExp: /^a$/ } }', this)
                verify(o, "QtQuick 2." + minor)
                o.destroy()
            }
        }
        function test_property_revisions_still_checked() {
            var failed = false
            try {
                // Item.containmentMask is QtQuick 2.11.
                Qt.createQmlObject('import QtQuick 2.0; Item { containmentMask: null }', this)
            } catch (e) {
                failed = true
            }
            verify(failed)
        }
    }
}
