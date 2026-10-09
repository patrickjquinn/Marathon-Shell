// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Theme API: values, methods and enumerations; Screen; Keel.Ambience
// defaults (no ambience in the environment).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Keel 1.0
import Sailfish.Silica 1.0 as Silica

TestCase {
    id: themeTest
    name: "Theme"

    function colorEqual(a, b) {
        return Qt.colorEqual(a, b)
    }

    function test_default_ambience() {
        compare(Theme.colorScheme, Theme.LightOnDark)
        compare(Theme.LightOnDark, 0)
        compare(Theme.DarkOnLight, 1)
        verify(colorEqual(Theme.primaryColor, "#ffffff"))
        // Sailfish's stock dark ambiences all use #bababa.
        verify(colorEqual(Theme.secondaryColor, "#bababa"))
        // Keel's own default ambience (keel/silica/ambience/).
        verify(colorEqual(Theme.highlightColor, "#7fd8ff"))
        verify(Theme.secondaryHighlightColor.hslLightness < Theme.highlightColor.hslLightness)
        verify(Theme.highlightDimmerColor.hslLightness < Theme.secondaryHighlightColor.hslLightness)
        compare(Theme.highlightBackgroundOpacity, 0.3)
        verify(colorEqual(Theme.lightPrimaryColor, "white"))
        verify(colorEqual(Theme.darkPrimaryColor, "black"))
        compare(Ambience.source, "defaults")
        compare(Ambience.pixelRatio, 0)
    }

    function test_geometry() {
        compare(Theme.pixelRatio, 1.0)
        compare(Theme.paddingSmall, 6)
        compare(Theme.paddingMedium, 12)
        compare(Theme.paddingLarge, 24)
        // Doubled on large screens; the offscreen test screen may count as one.
        verify(Theme.horizontalPageMargin === Theme.paddingLarge
               || Theme.horizontalPageMargin === 2 * Theme.paddingLarge)
        verify(Theme.itemSizeExtraSmall < Theme.itemSizeSmall)
        verify(Theme.itemSizeSmall < Theme.itemSizeMedium)
        verify(Theme.itemSizeMedium < Theme.itemSizeLarge)
        verify(Theme.itemSizeLarge < Theme.itemSizeExtraLarge)
        verify(Theme.itemSizeExtraLarge < Theme.itemSizeHuge)
        verify(Theme.iconSizeExtraSmall < Theme.iconSizeSmall)
        verify(Theme.iconSizeSmall < Theme.iconSizeSmallPlus)
        verify(Theme.iconSizeSmallPlus < Theme.iconSizeMedium)
        verify(Theme.iconSizeMedium < Theme.iconSizeLarge)
        verify(Theme.iconSizeLarge < Theme.iconSizeExtraLarge)
        verify(Theme.fontSizeTiny < Theme.fontSizeExtraSmall)
        verify(Theme.fontSizeExtraSmall < Theme.fontSizeSmall)
        verify(Theme.fontSizeSmall < Theme.fontSizeMedium)
        verify(Theme.fontSizeMedium < Theme.fontSizeLarge)
        verify(Theme.fontSizeLarge < Theme.fontSizeExtraLarge)
        verify(Theme.fontSizeExtraLarge < Theme.fontSizeHuge)
        compare(Theme.fontSizeMediumBase, Theme.fontSizeMedium)
        verify(Theme.buttonWidthTiny < Theme.buttonWidthExtraSmall)
        verify(Theme.buttonWidthSmall < Theme.buttonWidthMedium)
        verify(Theme.coverSizeSmall.width < Theme.coverSizeLarge.width)
        verify(Theme.maximumFlickVelocity > 0 && Theme.flickDeceleration > 0)
        verify(Theme.startDragDistance > 0)
        verify(Theme.opacityFaint < Theme.opacityLow && Theme.opacityLow < Theme.opacityHigh
               && Theme.opacityHigh < Theme.opacityOverlay)
        verify(Theme.fontFamily.length > 0 && Theme.fontFamilyHeading.length > 0)
    }

    function test_dp() {
        compare(Theme.dp(10), 10 * Theme.pixelRatio)
    }

    function test_rgba() {
        var c = Theme.rgba("#ff0000", 0.5)
        compare(c.r, 1)
        compare(c.g, 0)
        fuzzyCompare(c.a, 0.5, 0.01)
        var w = Theme.rgba(Theme.primaryColor, Theme.opacityLow)
        fuzzyCompare(w.a, 0.4, 0.01)
        compare(w.r, 1)
        // Replaces, not multiplies, an existing alpha.
        fuzzyCompare(Theme.rgba(Theme.secondaryColor, 1.0).a, 1.0, 0.01)
    }

    function test_highlightText() {
        compare(Theme.highlightText("Hello World", "world", "#ff0000"),
                "Hello <font color=\"#ff0000\">World</font>")
        compare(Theme.highlightText("a<b>&", "", "red"), "a&lt;b&gt;&amp;")
        compare(Theme.highlightText("abab", "b", "#00ff00"),
                "a<font color=\"#00ff00\">b</font>a<font color=\"#00ff00\">b</font>")
        compare(Theme.highlightText("x<y", "<", "#000000"), "x<font color=\"#000000\">&lt;</font>y")
    }

    function test_iconForMimeType() {
        compare(Theme.iconForMimeType("application/pdf"), "image://theme/icon-m-file-pdf")
        compare(Theme.iconForMimeType("image/png"), "image://theme/icon-m-file-image")
        compare(Theme.iconForMimeType("audio/mpeg"), "image://theme/icon-m-file-audio")
        compare(Theme.iconForMimeType("inode/directory"), "image://theme/icon-m-file-folder")
        compare(Theme.iconForMimeType("text/vcard"), "image://theme/icon-m-file-vcard")
        compare(Theme.iconForMimeType("application/vnd.oasis.opendocument.spreadsheet"),
                "image://theme/icon-m-file-spreadsheet")
        compare(Theme.iconForMimeType("application/x-unknown"), "image://theme/icon-m-file-other")
    }

    function test_derived_colors() {
        var h = Theme.highlightFromColor("#000040", Theme.LightOnDark)
        verify(Qt.lighter(h, 1.0).hslLightness > 0.3)
        var s = Theme.secondaryHighlightFromColor("#5cb8ff", Theme.LightOnDark)
        verify(Qt.lighter(s, 1.0).hslLightness < Qt.lighter("#5cb8ff", 1.0).hslLightness)
        var d = Theme.highlightDimmerFromColor("#5cb8ff", Theme.LightOnDark)
        verify(Qt.lighter(d, 1.0).hslLightness < Qt.lighter(s, 1.0).hslLightness)
        verify(Theme.highlightBackgroundFromColor("#5cb8ff", Theme.DarkOnLight) !== "")
    }

    // A palette with its own highlight colour and scheme derives the other
    // highlight colours through Keel.Ambience's helpers (whose scheme argument
    // the Rust bridge declares as ::std::int32_t: looked up by signature
    // "(QString,int)" they were "No such method" and the colours invalid).
    function test_palette_derived_colors() {
        var o = Qt.createQmlObject("import Sailfish.Silica 1.0; SilicaItem { "
                                   + "palette.highlightColor: \"#ff0000\"; palette.colorScheme: Theme.DarkOnLight }",
                                   themeTest, "paletteprobe")
        verify(Qt.colorEqual(o.palette.secondaryHighlightColor,
                             Theme.secondaryHighlightFromColor("#ff0000", Theme.DarkOnLight)))
        verify(Qt.colorEqual(o.palette.highlightBackgroundColor,
                             Theme.highlightBackgroundFromColor("#ff0000", Theme.DarkOnLight)))
        verify(Qt.colorEqual(o.palette.highlightDimmerColor,
                             Theme.highlightDimmerFromColor("#ff0000", Theme.DarkOnLight)))
        verify(o.palette.secondaryHighlightColor.a > 0)
        o.destroy()
    }

    function test_presence() {
        verify(!Qt.colorEqual(Theme.presenceColor(Theme.PresenceAvailable), Theme.presenceColor(Theme.PresenceBusy)))
        compare(Theme.PresenceOffline, 3)
    }

    function test_screen() {
        // Qualified: unqualified `Screen` is Qt Quick's (see COMPATIBILITY.md).
        verify(Silica.Screen.width <= Silica.Screen.height)
        fuzzyCompare(Silica.Screen.widthRatio, Silica.Screen.width / 540, 0.001)
        verify(Silica.Screen.sizeCategory >= Silica.Screen.Small
               && Silica.Screen.sizeCategory <= Silica.Screen.ExtraLarge)
        compare(Silica.Screen.Large, 2)
        // Qt Quick's Screen still answers width/height with Silica imported.
        verify(Screen.width > 0 && Screen.height > 0)
    }

    function test_clipboard() {
        Clipboard.text = "keel clipboard"
        compare(Clipboard.text, "keel clipboard")
        verify(Clipboard.hasText)
    }

    function test_shell_defaults() {
        verify(!Shell.underShell)
        verify(!Shell.connected)
        verify(!Shell.coverEnabled)
        compare(Shell.coverTitle, "keel:cover")
    }
}
