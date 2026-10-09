// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Screen. In Qt 6 a bare `Screen` in an expression is one import's that has
// the name: the first import's up to Qt 6.8, the last one's from Qt 6.10
// (outside keel/qt5compat's Qt Quick 2.x shims, which this test does not
// use). Qt Quick's attached Screen still gives the display size; qualified,
// Silica's full Screen API is always available. See COMPATIBILITY.md.
import Sailfish.Silica 1.0
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0 as S

TestCase {
    name: "Screen"
    when: windowShown

    Item {
        id: probe
        property int category: S.Screen.sizeCategory
        property bool large: S.Screen.sizeCategory >= S.Screen.Large
        property real ratio: S.Screen.widthRatio
    }

    function test_silica_screen() {
        compare(S.Screen.Small, 0)
        compare(S.Screen.Medium, 1)
        compare(S.Screen.Large, 2)
        compare(S.Screen.ExtraLarge, 3)
        verify(S.Screen.width > 0)
        verify(S.Screen.height >= S.Screen.width)
        compare(S.Screen.widthRatio, S.Screen.width / 540)
        verify(probe.category >= S.Screen.Small && probe.category <= S.Screen.ExtraLarge)
        compare(probe.large, probe.category >= 2)
        compare(probe.ratio, S.Screen.widthRatio)
        // A rectangle, as Silica's QML reads it (Screen.topCutout.height).
        compare(S.Screen.topCutout.height, 0)
        compare(S.Screen.hasCutouts, false)
        compare(S.Screen.topLeftCorner.radius, 0)
    }

    function test_qualified() {
        compare(S.Screen.Large, 2)
        compare(S.Screen.sizeCategory, probe.category)
    }

    // Which import's Screen an unqualified `Screen` names depends on Qt: up
    // to Qt 6.8 the first import that has the name wins, from Qt 6.10 the
    // last (checked on 6.4.2 and 6.11.2). Either way exactly one of the two
    // orders gives Silica's Screen, and Keel's own Qt 6 code qualifies:
    // S.Screen.
    function silicaScreenWith(imports) {
        var o = Qt.createQmlObject(imports + " QtObject { property var category: Screen.sizeCategory; "
                                   + "property var large: Screen.Large; property var ratio: Screen.pixelDensity }",
                                   probe, "importorder")
        var silica = o.category !== undefined
        if (silica) {
            compare(o.category, S.Screen.sizeCategory)
            compare(o.large, 2)
            // Qt Quick's members are there too (Keel's Screen is a superset).
            verify(o.ratio >= 0)
        }
        o.destroy()
        return silica
    }

    function test_silica_imported_first() {
        var first = silicaScreenWith("import Sailfish.Silica 1.0; import QtQuick;")
        var last = silicaScreenWith("import QtQuick; import Sailfish.Silica 1.0;")
        verify(first !== last, "exactly one import order gives Silica's Screen")
    }

    function test_usual_header_order() {
        var o = Qt.createQmlObject("import QtQuick 2.0; import Sailfish.Silica 1.0; "
                                   + "QtObject { property int w: Screen.width; property int h: Screen.height }",
                                   probe, "screenprobe")
        compare(Math.min(o.w, o.h), S.Screen.width)
        compare(Math.max(o.w, o.h), S.Screen.height)
        o.destroy()
    }
}
