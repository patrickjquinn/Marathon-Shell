// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One suggestion on the home: a row with an icon and the question, asked
// with one tap.

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: tile

    property string text
    property string icon            // pilotd's key: calendar, news, weather-day, ...

    Accessible.name: tile.text

    function source() {
        // The ambience decides which of a weather icon's two drawings
        // shows against it.
        var scheme = Theme.colorScheme === Theme.LightOnDark ? "dark" : "light";
        switch (icon) {
        case "calendar":
            return "image://theme/icon-m-date";
        case "news":
            return "image://theme/icon-m-website";
        case "weather-day":
            return "image://theme/icon-m-weather-d200-" + scheme;
        case "weather-night":
            return "image://theme/icon-m-weather-n200-" + scheme;
        case "alarm":
            return "image://theme/icon-m-alarm";
        case "reminder":
            return "image://theme/icon-m-note";
        default:
            return "image://theme/icon-m-timer";
        }
    }

    // Weather icons are drawn in colour; the rest take the theme colour.
    Image {
        objectName: "tileIcon"
        visible: tile.icon.indexOf("weather") === 0
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSizeMedium
        height: width
        sourceSize.width: width
        source: visible ? tile.source() : ""
    }
    Icon {
        objectName: "tileIcon"
        visible: tile.icon.indexOf("weather") !== 0
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        source: visible ? tile.source() : ""
        highlighted: tile.highlighted
    }

    Label {
        objectName: "question"
        x: Theme.horizontalPageMargin + Theme.iconSizeMedium + Theme.paddingLarge
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - Theme.horizontalPageMargin
        text: tile.text
        truncationMode: TruncationMode.Fade
        color: tile.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
}
