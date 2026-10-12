import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Library.js" as Library
import "../Playlists.js" as Playlists

ListItem {
    id: item

    property var music
    property var track
    property int playlistId: -1
    readonly property bool current: music.player.currentTrack !== null && music.player.currentTrack.path === track.path

    signal playRequested

    contentHeight: Theme.itemSizeMedium
    Accessible.name: qsTr("%1 by %2").arg(track.title).arg(track.artist)
    onClicked: playRequested()

    menu: ContextMenu {
        MenuItem {
            text: qsTr("Add to playlist")
            onClicked: pageStack.push(Qt.resolvedUrl("AddToPlaylistPage.qml"), { music: item.music, track: item.track })
        }
        MenuItem {
            visible: item.playlistId >= 0
            text: qsTr("Remove from playlist")
            onClicked: item.music.savePlaylists(Playlists.removeTrack(item.music.playlists, item.playlistId, item.track.path))
        }
    }

    Label {
        id: duration

        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        text: Library.formatTime(item.track.duration)
        font.pixelSize: Theme.fontSizeSmall
        color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
    }

    Column {
        x: Theme.horizontalPageMargin
        width: duration.x - x - Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter

        Label {
            width: parent.width
            text: item.track.title
            truncationMode: TruncationMode.Fade
            color: item.highlighted || item.current ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            text: item.track.artist
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            color: item.highlighted || item.current ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }
}
