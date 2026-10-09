// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Look fidelity on an Xperia 10 profile (1080x2520 offscreen screen, 6.0",
// pixelRatio 1.75; tests/CMakeLists.txt): the Theme values, colours, the
// ambience background and the glass glow measured from published Sailfish
// OS screenshots (screenshots/reference/SOURCES.md), so that they cannot
// regress unnoticed.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as KeelSilica
import Sailfish.Silica.private 1.0 as Private

Item {
    width: 540
    height: 960

    ApplicationWindow {
        id: appWindow
        width: 270
        height: 630
    }

    // A glass item without a size: Silica's TextSwitch and Switch rely on its
    // implicit size (Theme.itemSizeExtraSmall at the current pixelRatio).
    Private.GlassItem {
        id: sizeProbe
        visible: false
    }

    Rectangle {
        id: glassHolder
        x: 300
        width: 123
        height: 123
        color: "black"
        Private.GlassItem {
            anchors.fill: parent
            color: "white"
            radius: 0.22
            falloffRadius: 0.17
        }
    }

    TestCase {
        id: test
        name: "Fidelity"
        when: windowShown

        function test_device_metrics() {
            compare(KeelSilica.Screen.width, 1080)
            compare(KeelSilica.Screen.sizeCategory, KeelSilica.Screen.Medium)
            compare(Theme.pixelRatio, 1.75)
            compare(Theme.fontSizeExtraSmall, 42)
            compare(Theme.fontSizeSmall, 49)
            compare(Theme.fontSizeMedium, 56)
            compare(Theme.fontSizeLarge, 70)
            compare(Theme.fontSizeExtraLarge, 88)
            compare(Theme.paddingLarge, 42)
            compare(Theme.horizontalPageMargin, 48)
            compare(Theme.itemSizeExtraSmall, 123)
            compare(Theme.itemSizeSmall, 140)
            compare(Theme.buttonWidthSmall, 468)
            compare(Theme.fontFamily, "Sail Sans Pro Light")
            compare(Theme.fontFamilyHeading, "Sail Sans Pro Light")
        }

        function near(a, b, tolerance) {
            var x = Qt.lighter(a, 1.0), y = Qt.lighter(b, 1.0)
            return Math.abs(x.r - y.r) * 255 <= tolerance && Math.abs(x.g - y.g) * 255 <= tolerance
                    && Math.abs(x.b - y.b) * 255 <= tolerance
        }

        function test_ambience_colours() {
            verify(Qt.colorEqual(Theme.secondaryColor, "#bababa"))
            // Sailfish's water ambience: secondary highlight #62b9c4, and the
            // menu background of a fully saturated #7ff0fe.
            verify(near(Theme.secondaryHighlightFromColor("#7ff0fe", Theme.LightOnDark), "#62b9c4", 3))
            var hb = Qt.lighter(Theme.highlightBackgroundFromColor("#7ff0fe", Theme.LightOnDark), 1.0)
            verify(hb.r < 0.05 && hb.hsvSaturation > 0.95, "saturated: " + hb)
        }


        function findNamed(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            for (var i = 0; i < item.children.length; ++i) {
                var found = findNamed(item.children[i], name)
                if (found)
                    return found
            }
            return null
        }

        function test_window_draws_the_ambience() {
            var win = appWindow
            var wallpaper = findNamed(win, "keelAmbienceWallpaper")
            verify(wallpaper, "the window draws the ambience wallpaper")
            tryCompare(wallpaper, "status", Image.Ready, 5000)
            compare(wallpaper.source.toString().indexOf("image://keelambience/"), 0)
            waitForRendering(win)
            var image = grabImage(win)
            // Not a flat colour: the blurred wallpaper plus the dither.
            var colours = {}
            for (var y = 0; y < 630; y += 7)
                for (var x = 0; x < 270; x += 5)
                    colours[image.red(x, y) + "," + image.green(x, y) + "," + image.blue(x, y)] = true
            verify(Object.keys(colours).length > 40, Object.keys(colours).length + " colours")
            // Dark, as Sailfish dims the wallpaper behind apps.
            var l = (image.red(135, 315) + image.green(135, 315) + image.blue(135, 315)) / 3 / 255
            verify(l < 0.35, "lightness " + l)
        }


        // Mean brightness on a ring of radius r around the centre (the dither
        // makes single pixels meaningless).
        function ring(image, r) {
            var sum = 0, n = 0
            for (var a = 0; a < 360; a += 3) {
                var x = Math.round(61.5 + r * Math.cos(a * Math.PI / 180))
                var y = Math.round(61.5 + r * Math.sin(a * Math.PI / 180))
                sum += image.red(x, y) / 255
                ++n
            }
            return sum / n
        }

        function test_glass_default_size() {
            compare(sizeProbe.implicitWidth, Theme.itemSizeExtraSmall)
            compare(sizeProbe.implicitHeight, Theme.itemSizeExtraSmall)
        }

        function test_glass_glow_profile() {
            var item = glassHolder
            waitForRendering(item)
            var image = grabImage(item)
            // Measured on a checked TextSwitch: full at the centre, about half
            // at 0.13 of the height, a tenth at 0.30, nothing at the edge.
            verify(ring(image, 0) > 0.9, "centre " + ring(image, 0))
            var half = ring(image, 0.13 * 123)
            verify(half > 0.3 && half < 0.75, "at 0.13: " + half)
            var tenth = ring(image, 0.30 * 123)
            verify(tenth > 0.04 && tenth < 0.22, "at 0.30: " + tenth)
            verify(ring(image, 60) < 0.03, "edge " + ring(image, 60))
        }
    }
}
