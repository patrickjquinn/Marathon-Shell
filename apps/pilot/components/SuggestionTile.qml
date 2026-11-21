// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One suggestion on the home or in the overlay: a row with an icon and the
// question, asked with one tap. An answer's action is lit in the highlight.

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: tile

    property string text
    property string icon            // pilotd's key: calendar, news, weather-day, ...
    property bool action: false

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
        case "summary":
            return "image://theme/icon-m-document";
        case "explore":
            return "image://theme/icon-m-navigate";
        case "reply":
            return "image://theme/icon-m-reply";
        case "explain":
            return "image://theme/icon-m-about";
        case "points":
            return "image://theme/icon-m-menu";
        case "website":
            return "image://theme/icon-m-website";
        case "ask":
            return "image://theme/icon-m-message";
        case "open":
            return "image://theme/icon-m-up";
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
        highlighted: tile.highlighted || tile.action
    }

    Label {
        objectName: "question"
        x: Theme.horizontalPageMargin + Theme.iconSizeMedium + Theme.paddingLarge
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - Theme.horizontalPageMargin
        text: tile.text
        truncationMode: TruncationMode.Fade
        color: tile.highlighted || tile.action ? Theme.highlightColor : Theme.primaryColor
    }
}
