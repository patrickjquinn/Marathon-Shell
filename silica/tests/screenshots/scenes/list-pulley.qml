// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Reference scene: a SilicaListView of ListItems with its PullDownMenu
// dragged open (the tool drags without releasing). Written for Keel.
import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    width: 540
    height: 960
    cover: null
    property int shotDrag: 240
    property int shotDragY: 300
    initialPage: Component {
        Page {
            SilicaListView {
                anchors.fill: parent
                header: PageHeader { title: "Inbox" }
                model: 12
                PullDownMenu {
                    MenuItem { text: "Settings" }
                    MenuItem { text: "Sort by date" }
                    MenuItem { text: "New message" }
                }
                delegate: ListItem {
                    contentHeight: Theme.itemSizeSmall
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Message " + (index + 1)
                        color: highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
                VerticalScrollDecorator {}
            }
        }
    }
}
