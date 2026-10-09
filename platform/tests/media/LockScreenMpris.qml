// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// MprisPlayerControls as Jolla's lock screen sets it up (LockItem.qml):
// item width, text colour and button size bound when the item appears, the
// *Requested signals connected, shown while item.enabled.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Media 1.0

Item {
    id: root

    readonly property Item item: mpris.item
    readonly property bool shown: mpris.item !== null && mpris.item.enabled
    property int playPauseRequests
    property int nextRequests
    property int previousRequests

    function countPlayPause() { playPauseRequests++ }
    function countNext() { nextRequests++ }
    function countPrevious() { previousRequests++ }

    Item {
        id: mprisBackground
        width: root.width
        height: mpris.item ? mpris.item.height : 0
        visible: root.shown

        MprisPlayerControls {
            id: mpris

            onItemChanged: {
                if (item) {
                    item.textColor = Qt.binding(function() { return Theme.highlightColor })
                    item.width = Qt.binding(function() { return mprisBackground.width })
                    item.buttonSize = Theme.iconSizeLarge
                    item.playPauseRequested.connect(root.countPlayPause)
                    item.nextRequested.connect(root.countNext)
                    item.previousRequested.connect(root.countPrevious)
                }
            }
        }
    }
}
