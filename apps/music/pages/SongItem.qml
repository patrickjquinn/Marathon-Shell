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
    Accessible.name: current ? qsTr("%1 by %2, playing").arg(track.title).arg(track.artist) : qsTr("%1 by %2").arg(track.title).arg(track.artist)
    onClicked: playRequested()

    menu: ContextMenu {
        MenuItem {
            text: qsTr("Add to playlist")
            onClicked: pageStack.push(Qt.resolvedUrl("AddToPlaylistPage.qml"), {
                music: item.music,
                track: item.track
            })
        }
        MenuItem {
            objectName: "enqueueAction"
            text: qsTr("Add to play queue")
            onClicked: {
                item.music.player.enqueue(item.track);
                Notices.show(qsTr("Added to play queue"));
            }
        }
        MenuItem {
            objectName: "removeAction"
            visible: item.playlistId >= 0
            text: qsTr("Remove from playlist")
            onClicked: {
                const music = item.music;
                const playlistId = item.playlistId;
                const path = item.track.path;
                item.remorseAction(qsTr("Removed"), function () {
                    music.savePlaylists(Playlists.removeTrack(music.playlists, playlistId, path));
                });
            }
        }
    }

    TextMetrics {
        id: durationMetrics

        font.pixelSize: Theme.fontSizeLarge
        text: "00:00"
    }

    // Leading duration column, as in Jolla Media.
    Label {
        id: duration

        objectName: "duration"
        x: Theme.horizontalPageMargin
        width: durationMetrics.width
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Library.formatTime(item.track.duration)
        font.pixelSize: Theme.fontSizeLarge
        color: item.highlighted || item.current ? Theme.highlightColor : Theme.secondaryColor
    }

    Column {
        anchors {
            left: duration.right
            leftMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }

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
