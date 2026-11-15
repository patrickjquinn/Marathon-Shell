// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Choose a bookmark folder.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0

Page {
    id: page

    property int selected: 1
    signal picked(int id, string title)

    allowedOrientations: Orientation.All

    SilicaListView {
        anchors.fill: parent
        header: PageHeader { title: qsTr("Folder") }
        model: PacificList { kind: "folders"; revision: Pacific.revision }
        delegate: ListItem {
            id: item
            required property int itemId
            required property string title
            required property int depth
            highlighted: down || itemId === page.selected
            onClicked: {
                page.picked(itemId, title)
                pageStack.pop()
            }
            Label {
                x: Theme.horizontalPageMargin + item.depth * Theme.paddingLarge
                width: parent.width - x - Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: item.title
                textFormat: Text.PlainText
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
        }
        VerticalScrollDecorator {}
    }
}
