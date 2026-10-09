// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media 1.0 MediaPlayerControlsPanel, Keel's clean-room version: a
// bottom DockedPanel with a position slider, previous / play-pause / next
// buttons and optional repeat, shuffle and add-to-playlist buttons. Member
// names from the public Sailfish.Media documentation; the layout and the
// behaviour behind them are Keel's. `position` and `duration` are in
// `durationScalar` units (default 1000, milliseconds) and shown as seconds.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Media 1.0

DockedPanel {
    id: panel

    property bool active: true
    property bool playing
    property int position
    property int duration
    property int durationScalar: 1000
    property int repeat: MediaPlayerControls.NoRepeat
    property int shuffle: MediaPlayerControls.NoShuffle
    property bool showMenu: true
    property bool showAddToPlaylist
    property alias extraContentItem: extraContent
    property alias forwardEnabled: nextButton.enabled

    signal playPauseClicked()
    signal nextClicked()
    signal previousClicked()
    signal repeatClicked()
    signal shuffleClicked()
    signal addToPlaylist()
    signal sliderReleased(int value)

    function showControls() { open = true }
    function hideControls() { open = false }
    function hideMenu() { _menuOpen = false }

    property bool _menuOpen

    dock: Dock.Bottom
    width: parent ? parent.width : 0
    height: content.height + Theme.paddingLarge
    open: active

    MediaPlayerPanelBackground {
        anchors.fill: parent
    }

    Column {
        id: content
        width: parent.width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingMedium

        Slider {
            id: slider
            width: parent.width
            minimumValue: 0
            maximumValue: Math.max(1, panel.duration)
            value: panel.position
            enabled: panel.duration > 0
            valueText: Format.formatDuration(Math.round(value / Math.max(1, panel.durationScalar)),
                                             Formatter.DurationShort)
            onReleased: panel.sliderReleased(Math.round(value))
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingLarge

            IconButton {
                visible: panel.showMenu
                icon.source: panel.shuffle === MediaPlayerControls.NoShuffle
                             ? "image://theme/icon-m-shuffle" : "image://theme/icon-m-shuffle?" + Theme.highlightColor
                onClicked: panel.shuffleClicked()
            }
            IconButton {
                icon.source: "image://theme/icon-m-previous"
                onClicked: panel.previousClicked()
            }
            IconButton {
                icon.source: panel.playing ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
                onClicked: panel.playPauseClicked()
            }
            IconButton {
                id: nextButton
                icon.source: "image://theme/icon-m-next"
                onClicked: panel.nextClicked()
            }
            IconButton {
                visible: panel.showMenu
                icon.source: panel.repeat === MediaPlayerControls.NoRepeat
                             ? "image://theme/icon-m-repeat" : "image://theme/icon-m-repeat?" + Theme.highlightColor
                onClicked: panel.repeatClicked()
            }
            IconButton {
                visible: panel.showAddToPlaylist
                icon.source: "image://theme/icon-m-add"
                onClicked: panel.addToPlaylist()
            }
        }

        Item {
            id: extraContent
            width: parent.width
            height: childrenRect.height
        }
    }
}
