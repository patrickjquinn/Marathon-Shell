pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Library.js" as Library

Page {
    id: page

    property var music
    property string searchText
    property bool searchShown
    readonly property bool searching: searchText.trim() !== ""
    readonly property bool empty: music.tracks.length === 0
    readonly property string progressText: qsTr("Looking for music… %1%").arg(music.library ? music.library.scanProgress : 0)

    function countText(n, one, many) {
        return n === 1 ? one : many.arg(n);
    }

    SilicaListView {
        id: view

        objectName: "mainView"
        anchors.fill: parent
        model: page.searching ? Library.search(page.music.tracks, page.searchText) : []

        PullDownMenu {
            enabled: !page.empty
            MenuItem {
                objectName: "searchAction"
                text: page.searchShown ? qsTr("Hide search") : qsTr("Search")
                onClicked: page.searchShown = !page.searchShown
            }
            MenuItem {
                text: qsTr("Shuffle all")
                onClicked: page.music.player.shuffleTracks(page.music.tracks)
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
                visible: page.searchShown && !page.empty
                onTextChanged: page.searchText = text
                onVisibleChanged: {
                    if (visible)
                        forceActiveFocus();
                    else
                        text = "";
                }
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Repeater {
                objectName: "categories"
                model: page.searching || page.empty ? [] : [
                    {
                        name: qsTr("Playlists"),
                        icon: "media-playlists",
                        page: "PlaylistsPage.qml",
                        detail: page.countText(page.music.playlists.length, qsTr("1 playlist"), qsTr("%1 playlists"))
                    },
                    {
                        name: qsTr("All songs"),
                        icon: "media-songs",
                        page: "SongsPage.qml",
                        detail: page.countText(page.music.tracks.length, qsTr("1 song"), qsTr("%1 songs"))
                    },
                    {
                        name: qsTr("Albums"),
                        icon: "media-albums",
                        page: "AlbumsPage.qml",
                        detail: page.countText(page.music.albumCount, qsTr("1 album"), qsTr("%1 albums"))
                    },
                    {
                        name: qsTr("Artists"),
                        icon: "media-artists",
                        page: "ArtistsPage.qml",
                        detail: page.countText(page.music.artistCount, qsTr("1 artist"), qsTr("%1 artists"))
                    }
                ]

                ListItem {
                    id: category

                    required property var modelData

                    contentHeight: Theme.itemSizeMedium
                    Accessible.name: qsTr("%1, %2").arg(modelData.name).arg(modelData.detail)
                    onClicked: pageStack.push(Qt.resolvedUrl(modelData.page), modelData.page === "SongsPage.qml" ? {
                        music: page.music,
                        title: modelData.name,
                        tracks: Library.songs(page.music.tracks)
                    } : {
                        music: page.music
                    })

                    Icon {
                        id: categoryIcon

                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-" + category.modelData.icon
                        highlighted: category.highlighted
                    }
                    Column {
                        anchors {
                            left: categoryIcon.right
                            leftMargin: Theme.paddingLarge
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }

                        Label {
                            width: parent.width
                            text: category.modelData.name
                            truncationMode: TruncationMode.Fade
                            color: category.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: category.modelData.detail
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeSmall
                            color: category.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
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
            text: page.searching && !page.empty ? qsTr("No matches") : page.music.library ? qsTr("No music yet") : qsTr("Music library unavailable")
            hintText: page.searching && !page.empty ? "" : page.music.library ? qsTr("Copy audio files (MP3, FLAC, OGG and more) into the Music folder in your home folder. They appear here automatically.") : qsTr("Music couldn't connect to the music library, so your songs can't be listed.")
        }

        VerticalScrollDecorator {}
    }
}
