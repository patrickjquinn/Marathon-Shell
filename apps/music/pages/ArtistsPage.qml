pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Library.js" as Library

Page {
    id: page

    property var music

    SilicaListView {
        id: view

        anchors.fill: parent
        header: PageHeader { title: qsTr("Artists") }
        model: Library.artists(page.music.tracks)

        delegate: ListItem {
            id: item

            required property var modelData

            width: view.width
            contentHeight: Theme.itemSizeMedium
            Accessible.name: item.modelData.name
            onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"), { music: page.music, artist: item.modelData.name })

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: item.modelData.name
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: (item.modelData.albumCount === 1 ? qsTr("1 album") : qsTr("%1 albums").arg(item.modelData.albumCount)) + " · " + (item.modelData.trackCount === 1 ? qsTr("1 song") : qsTr("%1 songs").arg(item.modelData.trackCount))
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No artists")
        }

        VerticalScrollDecorator {}
    }
}
