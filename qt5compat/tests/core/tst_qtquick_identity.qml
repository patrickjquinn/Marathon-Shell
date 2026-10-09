// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Silica's BSD QML imports QtQuick 2.0 to 2.6, so under keel-shell every
// Silica file resolves QtQuick through the QtQuick.2.<minor> shim
// directories. The shims must hand out Qt's own Qt Quick types, not copies:
// the same C++ classes as `import QtQuick 2.15`, with Qt Quick's own
// attached properties, enums and singletons.
import QtQuick 2.15
import QtTest 1.0

Item {
    id: root

    function className(object) {
        return String(object).replace(/[(_].*$/, "")
    }

    TestCase {
        name: "QtQuickIdentity"

        function test_same_classes_data() {
            var rows = []
            for (var minor = 0; minor <= 14; ++minor)
                rows.push({ tag: "QtQuick 2." + minor, minor: minor })
            return rows
        }
        function test_same_classes(data) {
            var types = ["Item", "Rectangle", "Text", "MouseArea", "Flickable", "ListView",
                         "Image", "Timer", "PropertyAnimation"]
            for (var i = 0; i < types.length; ++i) {
                var real = Qt.createQmlObject("import QtQuick 2.15; " + types[i] + " { }", root)
                var shimmed = Qt.createQmlObject("import QtQuick 2." + data.minor + "; "
                                                 + types[i] + " { }", root)
                verify(real && shimmed, types[i])
                compare(className(shimmed), className(real), types[i])
                real.destroy()
                shimmed.destroy()
            }
        }
        function test_attached_and_enums() {
            // What Silica's ports rely on from Qt Quick under QtQuick 2.6.
            var o = Qt.createQmlObject(
                "import QtQuick 2.6; ListView {"
                + " property int snap: ListView.SnapToItem;"
                + " property int align: Text.AlignHCenter;"
                + " property real dist: Qt.styleHints.startDragDistance;"
                + " Keys.onPressed: { } }", root)
            verify(o)
            compare(o.snap, ListView.SnapToItem)
            compare(o.align, Text.AlignHCenter)
            verify(o.dist > 0)
            o.destroy()
        }
        function test_shim_types_present() {
            // And the directory really is the shim (Qt 5 names visible).
            var o = Qt.createQmlObject("import QtQuick 2.6; Item { property var v: RegExpValidator { } }", root)
            verify(o)
            o.destroy()
        }
    }
}
