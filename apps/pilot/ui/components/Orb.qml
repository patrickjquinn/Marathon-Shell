// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Pilot's presence: a soft glowing sphere in the ambience's highlight
// colour. Idle, it breathes. Listening, it swells with the voice and sends
// out ripples (`level`, 0 to 1, from the microphone). Thinking, an arc
// turns around it. Tap it to talk.

import QtQuick
import QtQuick.Shapes
import Sailfish.Silica 1.0

Item {
    id: orb

    // "idle", "listening", "thinking"
    property string mode: "idle"
    property real level: 0
    // A mic drawn on the core, for the small orb in the bar.
    property bool glyph: false
    signal clicked()

    implicitWidth: Theme.itemSizeMedium
    implicitHeight: implicitWidth

    // The voice, smoothed so the sphere moves like breath, not like a meter.
    property real _level: 0
    Behavior on _level { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    onLevelChanged: _level = mode === "listening" ? level : 0
    onModeChanged: if (mode !== "listening") _level = 0

    readonly property real _size: Math.min(width, height)

    // The glow: a radial gradient from the highlight colour to nothing.
    Shape {
        id: glow
        anchors.centerIn: parent
        width: orb._size * (0.95 + 0.35 * orb._level)
        height: width
        opacity: orb.enabled ? (orb.mode === "idle" ? 0.55 : 0.85) : 0.25
        Behavior on opacity { FadeAnimator {} }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: glow.width / 2; centerY: glow.height / 2
                centerRadius: glow.width / 2
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightColor, 0.75) }
                GradientStop { position: 0.45; color: Theme.rgba(Theme.highlightColor, 0.30) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            PathAngleArc {
                centerX: glow.width / 2; centerY: glow.height / 2
                radiusX: glow.width / 2; radiusY: glow.height / 2
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // Ripples while listening.
    Repeater {
        model: 3
        delegate: Rectangle {
            id: ripple
            required property int index
            anchors.centerIn: parent
            width: orb._size * 0.5
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, Theme.paddingSmall / 3)
            border.color: Theme.highlightColor
            opacity: 0
            visible: orb.mode === "listening"
            SequentialAnimation {
                running: ripple.visible
                loops: Animation.Infinite
                PauseAnimation { duration: ripple.index * 450 }
                ParallelAnimation {
                    NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.1; duration: 1350; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ripple; property: "opacity"; from: 0.55; to: 0; duration: 1350; easing.type: Easing.OutCubic }
                }
                PauseAnimation { duration: (2 - ripple.index) * 450 }
            }
        }
    }

    // The core: a lit sphere, light from above, with a soft rim.
    Item {
        id: core
        anchors.centerIn: parent
        width: orb._size * (orb.glyph ? 0.62 : 0.40)
        height: width
        scale: 1 + 0.45 * orb._level
        Shape {
            id: sphere
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                strokeColor: Theme.rgba(Qt.lighter(Theme.highlightColor, 1.4), 0.6)
                fillGradient: RadialGradient {
                    centerX: sphere.width * 0.5; centerY: sphere.height * 0.5
                    centerRadius: sphere.width * 0.5
                    focalX: sphere.width * 0.38; focalY: sphere.height * 0.30
                    GradientStop { position: 0.0; color: Qt.lighter(Theme.highlightColor, 1.45) }
                    GradientStop { position: 0.55; color: Theme.highlightColor }
                    GradientStop { position: 1.0; color: Qt.darker(Theme.highlightColor, 1.6) }
                }
                PathAngleArc {
                    centerX: sphere.width / 2; centerY: sphere.height / 2
                    radiusX: sphere.width / 2 - 0.5; radiusY: sphere.height / 2 - 0.5
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        // The mic, drawn small and filled so that it reads at a glance on
        // the lit sphere (Silica's icon-m-mic is a thin outline with no
        // small size): a capsule in a cradle on a stem, in the ambience's
        // dimmer highlight, a deep shade of the orb's own colour.
        Item {
            id: mic
            visible: orb.glyph && orb.mode === "idle"
            anchors.centerIn: parent
            width: orb._size * 0.3
            height: width * 1.3
            readonly property real line: Math.max(2, width * 0.1)
            readonly property color tone: Theme.highlightDimmerColor
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.46
                height: parent.height * 0.6
                radius: width / 2
                color: mic.tone
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: mic.line
                    strokeColor: mic.tone
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: mic.width * 0.1; startY: mic.height * 0.4
                    PathArc {
                        x: mic.width * 0.9; y: mic.height * 0.4
                        radiusX: mic.width * 0.4; radiusY: mic.height * 0.36
                        direction: PathArc.Counterclockwise
                    }
                }
                ShapePath {
                    strokeWidth: mic.line
                    strokeColor: mic.tone
                    capStyle: ShapePath.RoundCap
                    startX: mic.width / 2; startY: mic.height * 0.76
                    PathLine { x: mic.width / 2; y: mic.height - mic.line / 2 }
                }
            }
        }
        SequentialAnimation on scale {
            running: orb.mode === "idle" && orb.enabled && orb.visible && !orb.glyph
            loops: Animation.Infinite
            NumberAnimation { to: 1.08; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
        }
    }

    // Thinking: an arc turning around the core.
    Shape {
        id: arc
        anchors.centerIn: parent
        width: orb._size * 0.74
        height: width
        visible: orb.mode === "thinking"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.highlightColor
            strokeWidth: Math.max(3, orb._size / 40)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: arc.width / 2; centerY: arc.height / 2
                radiusX: arc.width / 2 - 2; radiusY: arc.height / 2 - 2
                startAngle: 0; sweepAngle: 100
            }
        }
        RotationAnimation on rotation {
            running: arc.visible
            from: 0; to: 360
            duration: 1100
            loops: Animation.Infinite
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: orb.enabled
        onClicked: orb.clicked()
    }
}
