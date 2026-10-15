import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// Now playing: the artwork, the track and how far through it is.
CoverBackground {
    id: cover

    property var track: null
    property url art
    property bool playing
    property real progress

    signal toggleRequested
    signal nextRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.track === null
        text: qsTr("Nothing playing")
        icon.source: "image://theme/icon-l-music"
    }

    Item {
        id: artwork

        visible: cover.track !== null
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: trackInfo.top
            margins: Theme.paddingLarge
            bottomMargin: Theme.paddingMedium
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            radius: Theme.paddingSmall
            color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

            Icon {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                source: "image://theme/icon-l-music"
                color: Theme.secondaryHighlightColor
            }
            Image {
                id: artImage

                objectName: "coverArt"
                anchors.fill: parent
                source: cover.art
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
    }

    Column {
        id: trackInfo

        objectName: "coverTrack"
        visible: cover.track !== null
        anchors {
            left: parent.left
            right: parent.right
            bottom: bar.top
            margins: Theme.paddingLarge
            bottomMargin: Theme.paddingMedium
        }

        Label {
            objectName: "coverTitle"
            width: parent.width
            text: cover.track ? cover.track.title : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
        }
        Label {
            width: parent.width
            text: cover.track ? cover.track.artist : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
        }
    }

    Rectangle {
        objectName: "coverTrackBar"
        visible: cover.track !== null
        x: bar.x
        y: bar.y
        width: cover.width - 2 * Theme.paddingLarge
        height: bar.height
        color: Theme.rgba(Theme.primaryColor, 0.2)
    }
    Rectangle {
        id: bar

        objectName: "coverProgress"
        visible: cover.track !== null
        anchors {
            left: parent.left
            leftMargin: Theme.paddingLarge
            bottom: cover.coverActionArea.top
        }
        height: Math.max(2, Math.round(Theme.paddingSmall / 2))
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
