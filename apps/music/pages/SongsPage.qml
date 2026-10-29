pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Playlists.js" as Playlists

Page {
    id: page

    property var music
    property string title
    property var tracks: []
    // A playlist's songs follow edits to it.
    property int playlistId: -1
    readonly property var shown: {
        if (playlistId < 0)
            return tracks;
        const list = music.playlists.find(p => p.id === playlistId);
        return list ? Playlists.tracksOf(list, music.tracks) : [];
    }

    SilicaListView {
        id: view

        objectName: "songsView"
        anchors.fill: parent
        header: PageHeader {
            title: page.title
        }
        model: page.shown

        PullDownMenu {
            enabled: view.count > 0
            MenuItem {
                text: qsTr("Shuffle")
                onClicked: page.music.player.shuffleTracks(page.shown)
            }
        }

        delegate: SongItem {
            required property var modelData
            required property int index

            width: view.width
            music: page.music
            track: modelData
            playlistId: page.playlistId
            onPlayRequested: page.music.player.playTracks(page.shown, index)
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No songs")
            hintText: page.playlistId >= 0 ? qsTr("Add songs from their menu in Songs, Albums or Artists") : ""
        }

        VerticalScrollDecorator {}
    }
}
