// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Screen's cutouts and rounded corners from the adaptation's dconf values
// (here KEEL_SCREEN_CUTOUTS and KEEL_SCREEN_ROUNDED_CORNERS, the Jolla
// Phone's: a 414x66 notch at the top centre, corners of radius 35 and 40).
// The offscreen screen is 1032x2272 at device pixel ratio 1. Also the
// Theme sizes Silica has there at pixelRatio 1.5 (read from Silica's own
// Theme on the phone).
import QtQuick
import QtTest
import Sailfish.Silica 1.0 as S

TestCase {
    name: "ScreenCutouts"

    function test_top_cutout() {
        verify(S.Screen.hasCutouts)
        compare(S.Screen.topCutout.x, 310)
        compare(S.Screen.topCutout.y, 0)
        compare(S.Screen.topCutout.width, 414)
        compare(S.Screen.topCutout.height, 66)
    }

    // A PageHeader inside a list's header item (a Column with the header and
    // more) keeps its title below the cut-out from its first layout: it used
    // to find its page only after the list had placed it, start in the
    // cut-out and then grow, leaving the title scrolled under the top.
    function test_page_header_in_list_header_clears_the_cutout() {
        var w = Qt.createQmlObject(
            "import QtQuick; import QtQuick.Window; import Sailfish.Silica 1.0\n"
            + "Window { width: 1032; height: 2272; visible: true\n"
            + "  property alias app: app\n"
            + "  ApplicationWindow { id: app; anchors.fill: parent; initialPage: Component { Page {\n"
            + "    SilicaListView { anchors.fill: parent; model: 3; delegate: Label { text: 'row' }\n"
            + "      header: Column { width: parent.width\n"
            + "        PageHeader { objectName: 'header'; title: 'Spelling languages'\n"
            + "          property real lowest: 1e9\n"
            + "          Component.onCompleted: lowest = Math.min(lowest, topMargin)\n"
            + "          onTopMarginChanged: lowest = Math.min(lowest, topMargin) }\n"
            + "        Label { width: parent.width; wrapMode: Text.Wrap; text: 'Words are checked against these languages.' } } } } } } }", this)
        tryVerify(function() { return w.app.pageStack.currentPage && !w.app.pageStack.busy })
        var header = findChild(w.app.pageStack.currentPage, "header")
        verify(header, "the header is there")
        tryVerify(function() { return header.page !== null && header.page !== undefined }, 2000, "it found its page")
        verify(header.lowest >= S.Screen.topCutout.height, "the title never started in the cut-out (" + header.lowest + ")")
        var title = header.mapToItem(w.app.pageStack.currentPage, 0, header.topMargin)
        verify(title.y >= S.Screen.topCutout.height, "the title is below the cut-out on the page (" + title.y + ")")
        w.destroy()
    }

    function test_rounded_corners() {
        compare(S.Screen.topLeftCorner.radius, 35)
        compare(S.Screen.topLeftCorner.x, 35)
        compare(S.Screen.topLeftCorner.y, 35)
        compare(S.Screen.topRightCorner.radius, 35)
        compare(S.Screen.topRightCorner.x, S.Screen.width - 35)
        compare(S.Screen.bottomLeftCorner.radius, 40)
        compare(S.Screen.bottomLeftCorner.y, S.Screen.height - 40)
        compare(S.Screen.bottomRightCorner.radius, 40)
        compare(S.Screen.bottomRightCorner.x, S.Screen.width - 40)
    }

    function test_jolla_phone_theme_sizes() {
        compare(S.Theme.pixelRatio, 1.5)
        compare(S.Theme._lineWidth, 4)
        compare(S.Theme.paddingSmall, 10)
        compare(S.Theme.paddingMedium, 20)
        compare(S.Theme.paddingLarge, 40)
        compare(S.Theme.horizontalPageMargin, 46)
        compare(S.Theme.itemSizeExtraSmall, 106)
        compare(S.Theme.itemSizeSmall, 120)
        compare(S.Theme.itemSizeMedium, 150)
        compare(S.Theme.itemSizeLarge, 166)
        compare(S.Theme.itemSizeExtraLarge, 202)
        compare(S.Theme.itemSizeHuge, 270)
        compare(S.Theme.iconSizeMedium, 96)
        compare(S.Theme.iconSizeLauncher, 128)
        compare(S.Theme.fontSizeExtraSmall, 36)
        compare(S.Theme.fontSizeMedium, 48)
        compare(S.Theme.fontSizeExtraLarge, 76)
        compare(S.Theme.buttonWidthSmall, 450)
        compare(S.Theme.buttonWidthMedium, 530)
        compare(S.Theme.buttonWidthLarge, 666)
        compare(S.Theme.startDragDistance, 30)
        compare(S.Theme.flickDeceleration, 2250)
        compare(S.Theme.maximumFlickVelocity, 11250)
        compare(String(S.Theme.lightSecondaryColor), "#bababa")
    }
}
