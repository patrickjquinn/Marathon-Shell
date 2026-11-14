// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// GridItemRemorseContainer (private): where a GridItem shows its remorse
// item below itself (loaded by Silica's BSD GridItem.qml, which then sets
// __silica_remorse_content). Silica's own file is not open (no BSD header in
// sailfishsilica-qt5 1.2.156); Keel's clean-room stand-in: an item under
// the grid item, as wide as the view.
import QtQuick
import Sailfish.Silica 1.0 as S // Silica's Screen (an unqualified Screen is Qt Quick's)

Item {
    id: container

    parent: gridItem
    y: gridItem.contentHeight
    x: gridItem._flickable ? -gridItem.mapToItem(gridItem._flickable, 0, 0).x : 0
    width: gridItem._flickable ? gridItem._flickable.width : S.Screen.width
    height: childrenRect.height
    z: 1000

    Component.onCompleted: gridItem.__silica_remorse_content = container
}
