// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Under the Qt Quick 2.x shims, an unqualified `Screen` is Silica's whatever
// the import order: the usual `import QtQuick 2.x` before Sailfish.Silica
// gave Qt Quick's attached Screen in Qt 6 (Silica's sizeCategory, topCutout
// and size enums undefined; found by Shoal Camera). The shims re-export
// Keel.SilicaScreen after Qt Quick. Code written for Qt Quick's Screen keeps
// its members (Keel's Screen is a superset).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as S

TestCase {
    name: "SilicaScreenShim"

    Item {
        id: probe
        property int category: Screen.sizeCategory
        property bool large: Screen.sizeCategory >= Screen.Large
    }

    function test_silica_members_unqualified() {
        compare(Screen.sizeCategory, S.Screen.sizeCategory)
        compare(Screen.Small, 0)
        compare(Screen.Medium, 1)
        compare(Screen.Large, 2)
        compare(Screen.ExtraLarge, 3)
        compare(Screen.widthRatio, S.Screen.widthRatio)
        compare(Screen.topCutout.height, 0)
        compare(Screen.hasCutouts, false)
        compare(Screen.width, S.Screen.width)
        compare(Screen.height, S.Screen.height)
        compare(probe.category, S.Screen.sizeCategory)
        compare(probe.large, S.Screen.sizeCategory >= 2)
    }

    function test_qt_quick_members() {
        verify(Screen.pixelDensity >= 0)
        verify(Screen.devicePixelRatio > 0)
        verify(Screen.desktopAvailableWidth > 0)
        verify(Screen.desktopAvailableHeight > 0)
        verify(typeof Screen.name === "string")
        verify(Screen.primaryOrientation === Qt.PortraitOrientation
               || Screen.primaryOrientation === Qt.LandscapeOrientation)
        verify(Screen.orientation !== undefined)
        compare(Screen.virtualX, 0)
    }

    function test_other_minor_versions_data() {
        var rows = []
        for (var minor = 0; minor <= 14; ++minor)
            rows.push({ tag: "QtQuick 2." + minor, minor: minor })
        return rows
    }
    function test_other_minor_versions(data) {
        var o = Qt.createQmlObject("import QtQuick 2." + data.minor + "; import Sailfish.Silica 1.0; "
                                   + "QtObject { property var category: Screen.sizeCategory; "
                                   + "property var large: Screen.Large }", probe, "screenshim")
        compare(o.category, S.Screen.sizeCategory)
        compare(o.large, 2)
        o.destroy()
    }
}
