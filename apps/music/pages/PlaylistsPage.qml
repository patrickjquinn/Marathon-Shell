pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Playlists.js" as Playlists

Page {
    id: page

    property var music

    SilicaListView {
        id: view

        objectName: "playlistsView"
        anchors.fill: parent
        header: PageHeader { title: qsTr("Playlists") }
        model: page.music.playlists

        PullDownMenu {
            MenuItem {
                text: qsTr("New playlist")
                onClicked: pageStack.push(Qt.resolvedUrl("NewPlaylistDialog.qml"), { music: page.music })
            }
        }

        delegate: ListItem {
            id: item

            required property var modelData

            width: view.width
            contentHeight: Theme.itemSizeMedium
            Accessible.name: item.modelData.name
            onClicked: pageStack.push(Qt.resolvedUrl("SongsPage.qml"), {
                music: page.music,
                title: item.modelData.name,
                playlistId: item.modelData.id
            })
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        page.music.savePlaylists(Playlists.remove(page.music.playlists, item.modelData.id));
                    })
                }
            }

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
                    text: (item.modelData.paths.length === 1 ? qsTr("1 song") : qsTr("%1 songs").arg(item.modelData.paths.length))
                    font.pixelSize: Theme.fontSizeSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No playlists")
            hintText: qsTr("Pull down to create one")
        }

        VerticalScrollDecorator {}
    }
}
