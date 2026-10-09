// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Silica.private Expander, Keel's own: content shown at
// `collapsedHeight` until tapped open to `expandedHeight`, with a fade over
// the cut-off edge while it is collapsed. Members as sailfish-components-
// webview's ContextMenu uses them (open, expandable, collapsedHeight,
// expandedHeight, horizontalMargin); the look is Keel's.
import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root

    property bool open
    property real collapsedHeight: Theme.itemSizeLarge
    property real expandedHeight: collapsedHeight
    property real horizontalMargin
    readonly property bool expandable: expandedHeight > collapsedHeight + 1
    default property alias contentData: contentItem.data

    height: open || !expandable ? expandedHeight : collapsedHeight
    clip: expandable
    Behavior on height {
        enabled: root.expandable
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }

    Item {
        id: contentItem
        width: parent.width
        height: root.expandedHeight
    }

    OpacityRampEffect {
        sourceItem: contentItem
        enabled: root.expandable && !root.open
        direction: OpacityRamp.TopToBottom
        offset: 0.5
        slope: 2
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.expandable
        onClicked: root.open = !root.open
    }
}
