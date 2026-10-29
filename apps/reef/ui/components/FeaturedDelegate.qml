// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One tile of a row of apps on the home page: the icon, the title, and
// one line under it, the app's category, or "Update" (highlighted, the
// only emphasis a tile has) when an update is waiting. Same roles as
// PackageDelegate (recentModel, and a collection's apps through appRow).

import QtQuick
import Sailfish.Silica 1.0

ListItem {
    id: tile

    required property string name
    required property string title
    required property string iconPath
    required property string categoryLabel
    required property string installState

    width: Theme.iconSizeLauncher + 2 * Theme.paddingLarge + Theme.paddingMedium
    contentHeight: Theme.iconSizeLauncher + Theme.paddingSmall + titleLabel.height + captionLabel.height + 2 * Theme.paddingMedium

    AppIcon {
        id: appIcon
        anchors.top: parent.top
        anchors.topMargin: Theme.paddingMedium
        anchors.horizontalCenter: parent.horizontalCenter
        iconPath: tile.iconPath
        title: tile.title
    }

    Label {
        id: titleLabel
        anchors.top: appIcon.bottom
        anchors.topMargin: Theme.paddingSmall
        width: parent.width - 2 * Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        // Always centred, a long one shortened with an ellipsis: a row of
        // tiles keeps one alignment.
        horizontalAlignment: Text.AlignHCenter
        text: tile.title
        color: tile.highlighted ? Theme.highlightColor : Theme.primaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        elide: Text.ElideRight
    }

    Label {
        id: captionLabel
        anchors.top: titleLabel.bottom
        width: parent.width - 2 * Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        // Always centred, a long one shortened with an ellipsis: a row of
        // tiles keeps one alignment.
        horizontalAlignment: Text.AlignHCenter
        text: tile.installState === "update_available" ? qsTr("Update") : tile.categoryLabel
        color: tile.installState === "update_available" ? Theme.highlightColor : tile.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        font.pixelSize: Theme.fontSizeTiny
        elide: Text.ElideRight
    }
}
