// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The screen's edges lit by Pilot, in the ambience's highlight colours:
// a soft bloom rising from the bottom edge, where the finger came from, when
// Pilot comes up, then a soft band all round that drifts between the
// highlight colours, and breathes faster while Pilot listens or thinks.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: glow

    // Lit while true; `intense` while Pilot listens or works.
    property bool active: false
    property bool intense: false

    readonly property real band: Theme.paddingLarge * 1.3
    // 0 to 1 around the colour drift.
    property real phase: 0
    // The rise from the bottom edge, 0 to 1 and back.
    property real bloom: 0

    opacity: active ? 1 : 0
    Behavior on opacity { FadeAnimator { duration: 250 } }

    NumberAnimation on phase {
        running: glow.active
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: glow.intense ? 2800 : 7000
    }
    onActiveChanged: if (active) rise.restart()
    SequentialAnimation {
        id: rise
        NumberAnimation { target: glow; property: "bloom"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: glow; property: "bloom"; to: 0; duration: 900; easing.type: Easing.InOutSine }
    }

    // How strongly an edge shows at its place in the drift.
    function strength(offset) {
        var p = (phase + offset) % 1
        var wave = 0.5 + 0.5 * Math.sin(p * 2 * Math.PI)
        return (intense ? 0.5 : 0.35) + (intense ? 0.25 : 0.15) * wave
    }

    // Bottom, with the bloom.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: glow.band + glow.bloom * glow.height * 0.16
        opacity: Math.max(glow.strength(0), glow.bloom * 0.8)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightColor, 0) }
            GradientStop { position: 0.45; color: Theme.rgba(Theme.highlightBackgroundColor, 0.08) }
            GradientStop { position: 0.8; color: Theme.rgba(Theme.highlightColor, 0.22) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightColor, 0.5) }
        }
    }
    // Top.
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: glow.band
        opacity: glow.strength(0.5)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightColor, 0.5) }
            GradientStop { position: 0.2; color: Theme.rgba(Theme.highlightColor, 0.22) }
            GradientStop { position: 0.55; color: Theme.rgba(Theme.highlightBackgroundColor, 0.08) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightColor, 0) }
        }
    }
    // Left.
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: glow.band
        opacity: glow.strength(0.25)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightColor, 0.5) }
            GradientStop { position: 0.2; color: Theme.rgba(Theme.highlightColor, 0.22) }
            GradientStop { position: 0.55; color: Theme.rgba(Theme.highlightBackgroundColor, 0.08) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightColor, 0) }
        }
    }
    // Right.
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: glow.band
        opacity: glow.strength(0.75)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightColor, 0) }
            GradientStop { position: 0.45; color: Theme.rgba(Theme.highlightBackgroundColor, 0.08) }
            GradientStop { position: 0.8; color: Theme.rgba(Theme.highlightColor, 0.22) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightColor, 0.5) }
        }
    }
}
