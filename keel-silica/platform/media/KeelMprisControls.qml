// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: MprisPlayerControls' item (see MprisPlayerControls.qml).
// The layout is Keel's.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Amber.Mpris 1.0

Item {
    id: controls

    property color textColor: Theme.primaryColor
    property real buttonSize: Theme.iconSizeLarge
    readonly property bool isPlaying: mpris.playbackStatus === Mpris.Playing
    // Keel: the controller, for apps that want more of the player.
    readonly property alias _controller: mpris

    signal playPauseRequested()
    signal nextRequested()
    signal previousRequested()

    enabled: mpris.availableServices.length > 0
    width: parent ? parent.width : implicitWidth
    implicitWidth: buttons.width
    height: column.height

    function _artist() {
        var artist = mpris.metaData.contributingArtist
        if (artist === undefined || artist === null)
            return ""
        if (typeof artist === "string")
            return artist
        // A string list (xesam:artist).
        var names = []
        for (var i = 0; i < artist.length; ++i)
            names.push(String(artist[i]))
        return names.join(", ")
    }

    MprisController {
        id: mpris
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            id: titleLabel
            objectName: "titleLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            color: controls.textColor
            text: mpris.metaData.title !== undefined && mpris.metaData.title !== null
                  ? String(mpris.metaData.title) : mpris.identity
        }

        Label {
            id: artistLabel
            objectName: "artistLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            color: controls.textColor
            opacity: Theme.opacityHigh
            text: controls._artist()
            visible: text.length > 0
        }

        Row {
            id: buttons
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingLarge

            IconButton {
                id: previousButton
                objectName: "previousButton"
                width: controls.buttonSize
                height: controls.buttonSize
                icon.source: "image://theme/icon-m-previous"
                icon.color: controls.textColor
                enabled: mpris.canGoPrevious
                onClicked: {
                    controls.previousRequested()
                    mpris.previous()
                }
            }
            IconButton {
                id: playPauseButton
                objectName: "playPauseButton"
                width: controls.buttonSize
                height: controls.buttonSize
                icon.source: controls.isPlaying ? "image://theme/icon-m-pause" : "image://theme/icon-m-play"
                icon.color: controls.textColor
                enabled: controls.isPlaying ? mpris.canPause : mpris.canPlay
                onClicked: {
                    controls.playPauseRequested()
                    mpris.playPause()
                }
            }
            IconButton {
                id: nextButton
                objectName: "nextButton"
                width: controls.buttonSize
                height: controls.buttonSize
                icon.source: "image://theme/icon-m-next"
                icon.color: controls.textColor
                enabled: mpris.canGoNext
                onClicked: {
                    controls.nextRequested()
                    mpris.next()
                }
            }
        }
    }
}
