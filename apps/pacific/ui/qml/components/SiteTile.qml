// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A site on the new-tab page: a letter tile and the site's name. Icons
// are not fetched from the network by the UI (that would bypass the
// browser's content blocking), so sites show their initial.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

BackgroundItem {
    id: tile

    property string siteTitle
    property string siteUrl
    property string iconSource

    width: Theme.itemSizeHuge
    height: letter.height + Theme.paddingSmall * 3 + nameMetrics.height * 2
    clip: true

    LetterIcon {
        id: letter
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Theme.paddingSmall
        }
        text: Logic.initial(tile.siteTitle, tile.siteUrl)
        url: tile.siteUrl
        iconSource: tile.iconSource
        highlighted: tile.highlighted
    }

    FontMetrics {
        id: nameMetrics
        font.pixelSize: Theme.fontSizeExtraSmall
    }

    // The site's short name (`wikipedia` for en.wikipedia.org), centred,
    // at most two lines, inside the cell.
    Label {
        anchors {
            top: letter.bottom
            topMargin: Theme.paddingSmall
            left: parent.left
            right: parent.right
            leftMargin: Theme.paddingSmall / 2
            rightMargin: Theme.paddingSmall / 2
        }
        horizontalAlignment: Text.AlignHCenter
        text: {
            var site = Pacific.siteName(tile.siteUrl);
            return site !== "" ? site : (tile.siteTitle !== "" ? tile.siteTitle : Logic.host(tile.siteUrl));
        }
        textFormat: Text.PlainText
        // Names of several words wrap between words; a long one-word name
        // is elided, never broken mid-word. No fontSizeMode: fitting with
        // wrapping and elision re-lays the text out on every frame, which
        // kept the main thread busy even with the new-tab page hidden.
        wrapMode: text.indexOf(" ") >= 0 ? Text.WordWrap : Text.NoWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.pixelSize: Theme.fontSizeExtraSmall
        color: tile.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
}
