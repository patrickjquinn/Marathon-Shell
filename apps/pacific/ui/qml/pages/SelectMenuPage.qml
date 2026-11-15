// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A page's drop-down list (<select>), as a Silica list.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var options: []
    property int selectedIndex: -1
    property var view
    property bool _answered: false

    allowedOrientations: Orientation.All

    Component.onDestruction: if (!_answered && view)
        view.closeSelectMenu()

    SilicaListView {
        anchors.fill: parent
        header: PageHeader {
            title: qsTr("Choose")
        }
        model: page.options
        delegate: ListItem {
            id: item
            required property var modelData
            required property int index
            enabled: modelData.enabled !== false && !modelData.groupLabel
            highlighted: down || index === page.selectedIndex
            onClicked: {
                page._answered = true;
                page.view.selectMenuOption(index);
                pageStack.pop();
            }
            Label {
                x: Theme.horizontalPageMargin + (item.modelData.groupChild ? Theme.paddingLarge : 0)
                width: parent.width - x - Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: item.modelData.groupLabel ? item.modelData.groupLabel : item.modelData.label
                textFormat: Text.PlainText
                truncationMode: TruncationMode.Fade
                color: item.modelData.groupLabel ? Theme.secondaryHighlightColor : (item.highlighted ? Theme.highlightColor : Theme.primaryColor)
                opacity: item.enabled || item.modelData.groupLabel ? 1.0 : Theme.opacityLow
            }
        }
        VerticalScrollDecorator {}
    }
}
