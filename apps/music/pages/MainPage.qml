pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Library.js" as Library

Page {
    id: page

    property var music
    property string searchText
    readonly property bool searching: searchText.trim() !== ""
    readonly property bool empty: music.tracks.length === 0
    readonly property string progressText: qsTr("Looking for music… %1%").arg(music.library ? music.library.scanProgress : 0)

    SilicaListView {
        id: view

        objectName: "mainView"
        anchors.fill: parent
        model: page.searching ? Library.search(page.music.tracks, page.searchText) : []

        PullDownMenu {
            enabled: !page.empty
            MenuItem {
                text: qsTr("Shuffle all")
                onClicked: {
                    page.music.player.shuffle = true;
                    page.music.player.playTracks(page.music.tracks, Math.floor(Math.random() * page.music.tracks.length));
                }
            }
        }

        header: Column {
            width: view.width

            PageHeader {
                objectName: "pageHeader"
                title: qsTr("Music")
                description: page.music.scanning && !page.empty ? page.progressText : ""
            }

            SearchField {
                id: searchField

                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search")
                visible: !page.empty
                onTextChanged: page.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Repeater {
                objectName: "categories"
                model: page.searching || page.empty ? [] : [
                    { name: qsTr("Artists"), icon: "media-artists", count: page.music.artistCount, page: "ArtistsPage.qml" },
                    { name: qsTr("Albums"), icon: "media-albums", count: page.music.albumCount, page: "AlbumsPage.qml" },
                    { name: qsTr("Songs"), icon: "media-songs", count: page.music.tracks.length, page: "SongsPage.qml" },
                    { name: qsTr("Playlists"), icon: "media-playlists", count: page.music.playlists.length, page: "PlaylistsPage.qml" }
                ]

                ListItem {
                    id: category

                    required property var modelData

                    contentHeight: Theme.itemSizeMedium
                    Accessible.name: qsTr("%1, %2").arg(modelData.name).arg(modelData.count)
                    onClicked: pageStack.push(Qt.resolvedUrl(modelData.page), modelData.page === "SongsPage.qml"
                                              ? { music: page.music, title: qsTr("Songs"), tracks: Library.songs(page.music.tracks) }
                                              : { music: page.music })

                    Icon {
                        id: categoryIcon

                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-" + category.modelData.icon
                        highlighted: category.highlighted
                    }
                    Label {
                        anchors {
                            left: categoryIcon.right
                            leftMargin: Theme.paddingLarge
                            right: count.left
                            rightMargin: Theme.paddingMedium
                            verticalCenter: parent.verticalCenter
                        }
                        text: category.modelData.name
                        truncationMode: TruncationMode.Fade
                        color: category.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        id: count

                        anchors {
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: category.modelData.count
                        color: category.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
            }
        }

        delegate: SongItem {
            required property var modelData
            required property int index

            width: view.width
            music: page.music
            track: modelData
            onPlayRequested: page.music.player.playTracks(view.model, index)
        }

        BusyLabel {
            objectName: "busyLabel"
            running: !page.music.loaded || (page.music.scanning && page.empty)
            text: page.music.scanning ? page.progressText : qsTr("Loading…")
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: page.music.loaded && !page.music.scanning && (page.empty || (page.searching && view.count === 0))
            text: page.searching && !page.empty ? qsTr("No matches")
                : page.music.library ? qsTr("No music yet") : qsTr("Music library unavailable")
            hintText: page.searching && !page.empty ? ""
                : page.music.library ? qsTr("Copy audio files (MP3, FLAC, OGG and more) into the Music folder in your home folder. They appear here automatically.")
                : qsTr("Music couldn't connect to the music library, so your songs can't be listed.")
        }

        VerticalScrollDecorator {}
    }
}
