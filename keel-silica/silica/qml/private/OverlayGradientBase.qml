// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// OverlayGradientBase (Sailfish.Silica.private): a vertical gradient from
// `startColor` to `endColor`; `noise` names a dithering texture
// (Silica's BSD private/OverlayGradient.qml). Keel's stand-in draws the
// gradient without the noise. Like Silica's native items it carries Silica's
// `palette` (Silica's OverlayGradient.qml reads palette.overlayBackgroundColor;
// Qt Quick's own Item.palette has no such colour).
import QtQuick
import Sailfish.Silica.private 1.0

Rectangle {
    id: overlayGradient

    /*override*/ readonly property Palette palette: Palette {}
    property color startColor
    property color endColor
    property url noise

    gradient: Gradient {
        GradientStop { position: 0.0; color: overlayGradient.startColor }
        GradientStop { position: 1.0; color: overlayGradient.endColor }
    }
}
