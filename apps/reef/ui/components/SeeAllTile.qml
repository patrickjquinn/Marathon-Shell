// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// The last tile of a row of apps: opens the whole list. Sized and laid out
// as an app tile (FeaturedDelegate), with an arrow where the icon is, so
// the row ends in the same rhythm.

import QtQuick
import Sailfish.Silica 1.0

ListItem {
    id: tile

    width: Theme.iconSizeLauncher + 2 * Theme.paddingLarge + Theme.paddingMedium
    contentHeight: Theme.iconSizeLauncher + Theme.paddingSmall + label.height * 2 + 2 * Theme.paddingMedium

    // The theme's arrow (a circle of its own on the phone), centred where
    // a tile's icon is, nothing around it.
    Item {
        id: badge
        anchors.top: parent.top
        anchors.topMargin: Theme.paddingMedium
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.iconSizeLauncher
        height: width

        Icon {
            anchors.centerIn: parent
            source: "image://theme/icon-m-right"
            highlighted: tile.highlighted
        }
    }

    Label {
        id: label
        anchors.top: badge.bottom
        anchors.topMargin: Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 2 * Theme.paddingSmall
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("See all")
        color: tile.highlighted ? Theme.highlightColor : Theme.primaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        truncationMode: TruncationMode.Fade
    }
}
