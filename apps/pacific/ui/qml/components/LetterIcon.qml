// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// A site's icon: its cached favicon on a rounded plate, or, until there is
// one, its initial on a colour of its own (a hue from the host, so a site
// keeps its colour everywhere).

import QtQuick
import Sailfish.Silica 1.0
import "../js/logic.js" as Logic

Item {
    id: icon

    property string text
    property string url
    property string iconSource
    property bool highlighted

    width: Theme.iconSizeLarge
    height: width

    Rectangle {
        anchors.fill: parent
        radius: width / 4
        // The site's own colour, kept dim enough for white text.
        color: favicon.status === Image.Ready ? Theme.rgba(Theme.primaryColor, 0.9)
                                              : Qt.hsla(Logic.hostHue(icon.url), 0.45, 0.38, 1.0)
        border.width: icon.highlighted ? Theme.paddingSmall / 2 : 0
        border.color: Theme.highlightColor
    }

    Image {
        id: favicon
        anchors.centerIn: parent
        width: parent.width * 0.7
        height: width
        source: icon.iconSource
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
    }

    Label {
        anchors.centerIn: parent
        visible: favicon.status !== Image.Ready
        text: icon.text
        font.pixelSize: icon.width * 0.45
        font.bold: true
        textFormat: Text.PlainText
        color: Theme.lightPrimaryColor
    }
}
