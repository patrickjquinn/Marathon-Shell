// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ColorBackground (Sailfish.Silica.Background): a filled background with
// `color`, `radius` and `roundedCorners` (Corners flags; default all).
// Names from Silica's BSD QML (RemorseBase, Scrollbar, BannerBackground);
// Silica's own file is proprietary. Keel's clean-room stand-in: a rounded
// rectangle with square patches over the corners that are not rounded,
// with the SilicaItem `highlighted` and `palette` the BSD QML reads.
import QtQuick
import Sailfish.Silica.private 1.0

Item {
    id: root

    readonly property bool __keel_silica_style: true
    property bool highlighted: palette._parentHighlighted
    /*override*/ readonly property Palette palette: Palette {}

    property color color
    property real radius
    property int roundedCorners: Corners.All

    Rectangle {
        anchors.fill: parent
        color: root.color
        radius: root.radius
    }
    component SquareCorner: Rectangle {
        property int flag
        property bool atRight
        property bool atBottom
        visible: root.radius > 0 && !(root.roundedCorners & flag)
        width: Math.min(root.radius, root.width / 2)
        height: Math.min(root.radius, root.height / 2)
        x: atRight ? root.width - width : 0
        y: atBottom ? root.height - height : 0
        color: root.color
    }
    SquareCorner { flag: Corners.TopLeft }
    SquareCorner { flag: Corners.TopRight; atRight: true }
    SquareCorner { flag: Corners.BottomLeft; atBottom: true }
    SquareCorner { flag: Corners.BottomRight; atRight: true; atBottom: true }
}
