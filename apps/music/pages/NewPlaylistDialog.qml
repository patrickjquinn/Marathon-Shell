import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Playlists.js" as Playlists

Dialog {
    id: dialog

    property var music
    // Set to add this track to the new playlist.
    property var track: null

    canAccept: nameField.text.trim() !== ""
    onAccepted: {
        let next = Playlists.create(music.playlists, nameField.text.trim());
        if (track)
            next = Playlists.addTrack(next, next[next.length - 1].id, track.path);
        music.savePlaylists(next);
    }

    Column {
        width: parent.width

        DialogHeader {
            title: qsTr("New playlist")
        }

        TextField {
            id: nameField

            objectName: "nameField"
            width: parent.width
            focus: true
            label: qsTr("Name")
            placeholderText: qsTr("Playlist name")
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
