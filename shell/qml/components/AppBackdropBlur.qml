import MarathonOS.Shell
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

// Live-blur backdrop over a target QQuickItem (typically the running app's
// WaylandShellSurfaceItem). Used by Lock Screen and Quick Settings to give
// the chrome an iOS-style glass-over-app coherence that competing Wayland
// phone shells can't match: they'd need ext-image-copy-capture-v1 per frame
// across IPC, whereas Marathon samples the surface texture inline.
//
// Render path: ShaderEffectSource samples `source` → MultiEffect blurs it.
// Per coding-rules C8, `live` is gated on this item's visibility so the
// GPU isn't burning samples while the chrome is hidden.
Item {
    id: root

    // The Item to blur. Pass appWindowContainer when an app is open;
    // pass null (or a wallpaper item) otherwise.
    property Item source

    property real blurAmount: 1.0
    property real blurMax: 48
    property real saturation: 0.5
    property real brightness: -0.1
    property color tint: Qt.rgba(0, 0, 0, 0.2)

    visible: source !== null

    ShaderEffectSource {
        id: capture

        anchors.fill: parent
        sourceItem: root.source
        live: root.visible && root.source !== null
        hideSource: false
        recursive: false
        // RGBA16F keeps the colour chain linear-precise across the blur
        // → tint composite. With 8-bit RGBA you get dark-fringe gamma
        // error around bright pixels (white app text against teal-glow
        // tint shows a brown halo).
        //
        // Gated on Constants.gpuHdr (set via MARATHON_GPU_HDR env, read
        // by shell/runner C++). The Librem 5's etnaviv GC7000Lite can't
        // expose RGBA16F as a colour buffer attachment — QRhi logs
        // "QSGRhiLayer: Attempted to set unsupported texture format 8"
        // on every blur compose. RGBA fallback gives a slightly darker
        // halo but eliminates the per-frame spam. Default off; enable
        // on capable GPUs (Mali / Mesa-virgl / Apple GPU).
        format: Constants.gpuHdr ? ShaderEffectSource.RGBA16F : ShaderEffectSource.RGBA
        // Mipmap so MultiEffect's wide-kernel reads sample a pre-filtered
        // chain rather than re-blurring 32× per pixel — visibly smoother
        // bokeh, lower fillrate cost.
        mipmap: true
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: capture
        blurEnabled: true
        blur: root.blurAmount
        blurMax: root.blurMax
        blurMultiplier: 1
        saturation: root.saturation
        brightness: root.brightness
    }

    Rectangle {
        anchors.fill: parent
        color: root.tint
    }
}
