// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Frosted glass, as iOS draws its bars: what is behind, blurred, its colours
// lifted, under a tint of the theme's overlay colour.
//
// Cheap at the panel's rate: only the strip of `backdrop` under the glass is
// captured (with a margin above it, so the top edge blurs into what is
// there), at half its resolution, and blurred at that size by MultiEffect
// (a few small passes at decreasing sizes, not a full-screen Gaussian).
// Nothing is captured while the glass is off screen or `active` is false.
// The web view's frames are textures in the scene graph, so the capture
// draws one textured quad into a small target: no copy of the page.
import QtQuick
import QtQuick.Effects
import Sailfish.Silica

Item {
    id: glass

    // What is behind the glass, and where the glass's top edge is in its
    // coordinates.
    property Item backdrop
    property real backdropX: 0
    property real backdropY: 0
    property bool active: true
    property color tint: Theme.overlayBackgroundColor
    property real tintOpacity: 0.62

    // The rows above the glass that blur into its top edge.
    readonly property real margin: Math.round(Theme.paddingLarge * 1.5)
    readonly property bool capturing: active && backdrop !== null && visible && width > 0 && height > 0

    clip: true

    ShaderEffectSource {
        id: capture

        visible: false
        sourceItem: glass.capturing ? glass.backdrop : null
        live: glass.capturing
        hideSource: false
        recursive: false
        smooth: true
        sourceRect: Qt.rect(glass.backdropX, glass.backdropY - glass.margin, glass.width, glass.height + glass.margin)
        // Half resolution: the blur that follows cannot tell, and it is a
        // quarter of the pixels to capture and to blur.
        textureSize: Qt.size(Math.max(1, Math.ceil(glass.width / 2)), Math.max(1, Math.ceil((glass.height + glass.margin) / 2)))
    }

    MultiEffect {
        x: 0
        y: -glass.margin
        width: glass.width
        height: glass.height + glass.margin
        visible: glass.capturing
        source: capture
        autoPaddingEnabled: false
        blurEnabled: true
        // Never animated: a change of blurMax rebuilds the shaders.
        blurMax: 64
        blur: 1.0
        blurMultiplier: 1.0
        // Colours lifted under the blur, as iOS's materials do.
        saturation: 0.35
    }

    Rectangle {
        anchors.fill: parent
        color: glass.tint
        // Without a backdrop (or while it is not captured) the glass is the
        // old opaque one.
        opacity: glass.capturing ? glass.tintOpacity : 0.948
    }
}
