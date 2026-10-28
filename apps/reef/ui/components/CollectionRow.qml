// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// One collection on the home page (collectionsModel): a section header and
// its apps as a row of tiles, ending in a See all tile that opens the whole
// collection. The row's model is the collection's app names; each tile
// reads its app's row from Reef.appRow, again whenever the models are
// rebuilt (Reef.revision).

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0

Column {
    id: collection

    // collectionsModel's roles.
    required property string title
    required property var apps

    signal openApp(string name)
    signal openAll()

    width: parent ? parent.width : 0

    SectionHeader {
        text: collection.title
    }

    SilicaListView {
        width: parent.width
        // The tiles' height (FeaturedDelegate: icon, title, one line).
        height: Theme.iconSizeLauncher + 2 * Theme.fontSizeExtraSmall * 1.4 + 2 * Theme.paddingMedium
        orientation: ListView.Horizontal
        clip: true
        model: collection.apps
        header: Item { width: Theme.horizontalPageMargin - Theme.paddingLarge; height: 1 }
        footer: SeeAllTile {
            onClicked: collection.openAll()
        }
        delegate: FeaturedDelegate {
            id: tile
            required property string modelData
            readonly property var info: {
                const revision = Reef.revision
                return revision >= 0 ? Reef.appRow(modelData) : ({})
            }
            name: modelData
            title: info.title || ""
            iconPath: info.iconPath || ""
            categoryLabel: info.categoryLabel || ""
            installState: info.installState || "not_installed"
            onClicked: collection.openApp(tile.modelData)
        }
    }
}
