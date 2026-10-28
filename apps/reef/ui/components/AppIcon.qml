// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// An app's launcher icon from the repository's asset cache, or, until it is
// cached, a placeholder with the app's initial. The path is a local file the
// Rust side downloaded from the pinned repository (README, "Assets"); the
// store never loads an image from a URL in the catalogue.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: icon

    property string iconPath
    property string title
    property real size: Theme.iconSizeLauncher

    width: size
    height: size

    Rectangle {
        anchors.fill: parent
        radius: Math.round(parent.width / 5)
        color: Theme.secondaryHighlightColor
        opacity: Theme.opacityFaint
        visible: image.status !== Image.Ready
    }

    Label {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: icon.title.length > 0 ? icon.title.charAt(0).toUpperCase() : ""
        textFormat: Text.PlainText
        color: Theme.highlightColor
        font.pixelSize: Math.round(icon.size * 0.5)
    }

    Image {
        id: image
        anchors.fill: parent
        source: icon.iconPath.length > 0 ? "file://" + icon.iconPath : ""
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }
}
