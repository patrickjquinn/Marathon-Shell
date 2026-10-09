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
