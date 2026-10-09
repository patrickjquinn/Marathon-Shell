// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media 1.0 MprisPlayerControls, Keel's clean-room version: a
// Loader whose item shows and controls the current MPRIS player (title,
// artist, previous / play-pause / next) through Amber.Mpris's
// MprisController. API from its one public user, Jolla's lock screen
// (lipstick-jolla-home's LockItem.qml): the item's `textColor`, `width`,
// `buttonSize`, `isPlaying`, `enabled` (true while a player is on the bus,
// then the lock screen's to set) and the `playPauseRequested`,
// `nextRequested` and `previousRequested` signals, emitted before the call
// goes to the player. The item stays null when Amber.Mpris is not
// installed.
import QtQuick 2.6

Loader {
    source: Qt.resolvedUrl("KeelMprisControls.qml")
}
