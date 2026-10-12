import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

CoverBackground {
    id: cover

    property var track: null
    property bool playing
    property real progress

    signal toggleRequested
    signal nextRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.track === null
        text: qsTr("Music")
        icon.source: "image://theme/icon-l-music"
    }

    Column {
        objectName: "coverTrack"
        visible: cover.track !== null
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            objectName: "coverTitle"
            width: parent.width
            text: cover.track ? cover.track.title : ""
            font.pixelSize: Theme.fontSizeLarge
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            text: cover.track ? cover.track.artist : ""
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryColor
            truncationMode: TruncationMode.Fade
        }
    }

    Rectangle {
        id: bar

        objectName: "coverProgress"
        visible: cover.track !== null
        anchors {
            left: parent.left
            leftMargin: Theme.paddingLarge
            bottom: cover.coverActionArea.top
            bottomMargin: Theme.paddingMedium
        }
        height: Theme.paddingSmall / 2
        color: Theme.highlightColor
    }

    // The bar only follows playback while the cover is on screen.
    Binding {
        target: bar
        property: "width"
        when: cover.status === Cover.Active
        value: (cover.width - 2 * Theme.paddingLarge) * cover.progress
        restoreMode: Binding.RestoreNone
    }

    CoverActionList {
        enabled: cover.track !== null

        CoverAction {
            objectName: "coverPlayPause"
            iconSource: cover.playing ? "image://theme/icon-cover-pause" : "image://theme/icon-cover-play"
            onTriggered: cover.toggleRequested()
        }
        CoverAction {
            objectName: "coverNext"
            iconSource: "image://theme/icon-cover-next-song"
            onTriggered: cover.nextRequested()
        }
    }
}
