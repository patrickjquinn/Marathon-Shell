// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TouchBlocker: accepts all mouse and touch input (Silica public
// documentation); clean-room.
import QtQuick

MouseArea {
    preventStealing: true
    hoverEnabled: true
    onWheel: function(wheel) { wheel.accepted = true }
}
