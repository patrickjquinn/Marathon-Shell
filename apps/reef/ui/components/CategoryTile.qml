// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One category in the home page's grid (categoriesModel): its theme icon
// and its name, on one line. How many apps it has is on its own page.

import QtQuick
import Sailfish.Silica 1.0

BackgroundItem {
    id: tile

    required property string categoryId
    required property string label
    required property string icon

    height: Theme.itemSizeSmall

    Icon {
        id: glyph
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        // A catalogue without a category list names no icons.
        source: "image://theme/" + (tile.icon.length > 0 ? tile.icon : "icon-m-other")
        highlighted: tile.highlighted
    }
    Label {
        anchors.left: glyph.right
        anchors.leftMargin: Theme.paddingMedium
        anchors.right: parent.right
        anchors.rightMargin: Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter
        text: tile.label
        textFormat: Text.PlainText
        color: tile.highlighted ? Theme.highlightColor : Theme.primaryColor
        truncationMode: TruncationMode.Fade
    }
}
