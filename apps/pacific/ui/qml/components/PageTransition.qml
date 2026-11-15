// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The page being left, blurred in place until the next one shows (WebTab).
//
// When `changing` turns true (a navigation started) the view is captured
// once, as it is on screen: the web view's frame is a texture in the scene
// graph, so this is one textured quad drawn into a target the size of the
// view, before the old page's buffers go. The copy stays sharp for 350 ms,
// then blurs in over 300 ms while the next page loads. When `changing`
// turns false the next page has painted under it, and the copy fades out
// over 200 ms. A change that ended without a new page (a download, Stop)
// fades the copy away the same way, onto the old page, still there.
import QtQuick
import QtQuick.Effects
import Sailfish.Silica

Item {
    id: transition

    property Item view
    property bool changing
    // On screen, blurring in or fading out: the web view must draw through
    // Qt meanwhile (its own subsurface would cover this).
    readonly property bool shown: copy.opacity > 0

    onChangingChanged: {
        if (changing) {
            fadeOut.stop()
            capture.scheduleUpdate()
            copy.opacity = 1
            blurIn.restart()
        } else if (copy.opacity > 0) {
            blurIn.stop()
            fadeOut.restart()
        }
    }

    ShaderEffectSource {
        id: capture
        anchors.fill: parent
        visible: false
        sourceItem: transition.view
        live: false
        hideSource: false
        recursive: false
        // Half resolution: it is blurred, and a quarter of the pixels.
        textureSize: Qt.size(Math.max(1, Math.ceil(width / 2)), Math.max(1, Math.ceil(height / 2)))
    }

    Item {
        id: copy
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0

        // Under the blur's soft edges: the page's background, not the
        // frames below.
        Rectangle {
            anchors.fill: parent
            color: Theme.lightPrimaryColor
        }

        MultiEffect {
            id: blurred
            anchors.fill: parent
            source: capture
            autoPaddingEnabled: false
            blurEnabled: true
            // Never animated: a change of blurMax rebuilds the shaders.
            blurMax: 64
            blurMultiplier: 1.0
            blur: 0
            // Dimmed a little as it blurs: the page is going, not loading.
            brightness: -0.04 * blur
        }
    }

    // Sharp at first (the copy looks just like the page), blurring only
    // once the change takes a while: a page that loads quickly fades in
    // over the old one with no blur at all, and a slow one shows that it
    // is on its way.
    SequentialAnimation {
        id: blurIn
        PauseAnimation {
            duration: 350
        }
        NumberAnimation {
            target: blurred
            property: "blur"
            from: 0
            to: 1
            duration: 300
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation {
        id: fadeOut
        NumberAnimation {
            target: copy
            property: "opacity"
            to: 0
            duration: 200
            easing.type: Easing.InOutQuad
        }
        ScriptAction {
            script: blurred.blur = 0
        }
    }
}
