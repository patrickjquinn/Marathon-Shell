// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One suggestion on the home: a glass tile with an icon and the question,
// asked with one tap.

import QtQuick
import Sailfish.Silica 1.0

BackgroundItem {
    id: tile

    property string text
    property string icon            // pilotd's key: calendar, news, weather-day, ...

    function source() {
        // The ambience decides which of a weather icon's two drawings
        // shows against it.
        var scheme = Theme.colorScheme === Theme.LightOnDark ? "dark" : "light"
        switch (icon) {
        case "calendar": return "image://theme/icon-m-date"
        case "news": return "image://theme/icon-m-website"
        case "weather-day": return "image://theme/icon-m-weather-d200-" + scheme
        case "weather-night": return "image://theme/icon-m-weather-n200-" + scheme
        case "alarm": return "image://theme/icon-m-alarm"
        case "reminder": return "image://theme/icon-m-note"
        default: return "image://theme/icon-m-timer"
        }
    }

    // Room for the icon and two lines of the question below it at the
    // person's text size: every tile the same height, and a question that
    // wraps never runs into its icon, and as much room below the question
    // as above the icon (lines measured with their leading, as drawn).
    readonly property real _textTop: Theme.paddingLarge + Theme.iconSizeMedium + Theme.paddingSmall
    height: Math.max(Theme.itemSizeExtraLarge, _textTop + 2 * questionMetrics.lineSpacing + Theme.paddingLarge)
    FontMetrics {
        id: questionMetrics
        font.pixelSize: Theme.fontSizeSmall
    }
    _backgroundColor: "transparent"
    highlightedColor: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: Theme.paddingLarge
        color: tile.down ? Theme.rgba(Theme.highlightBackgroundColor, 0.30)
                         : Theme.rgba(Theme.primaryColor, 0.06)
        border.width: 1
        border.color: Theme.rgba(Theme.primaryColor, 0.10)
    }

    // Weather icons are drawn in colour; the rest take the theme colour.
    Image {
        objectName: "tileIcon"
        visible: tile.icon.indexOf("weather") === 0
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: Theme.iconSizeMedium
        height: width
        sourceSize.width: width
        source: visible ? tile.source() : ""
    }
    Icon {
        objectName: "tileIcon"
        visible: tile.icon.indexOf("weather") !== 0
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        source: visible ? tile.source() : ""
        color: Theme.highlightColor
    }

    Label {
        objectName: "question"
        x: Theme.paddingLarge
        y: tile._textTop
        width: parent.width - 2 * Theme.paddingLarge
        text: tile.text
        wrapMode: Text.Wrap
        maximumLineCount: 2
        truncationMode: TruncationMode.Fade
        font.pixelSize: Theme.fontSizeSmall
        color: tile.down ? Theme.highlightColor : Theme.primaryColor
    }
}
