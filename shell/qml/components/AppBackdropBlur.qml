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

    // Region of `source` to capture, in the source item's coordinates. Default
    // Qt.rect(0,0,0,0) = the whole source (ShaderEffectSource's "empty = all"
    // rule). Set this to a rect the SAME SIZE as this blur item to avoid the
    // source being squashed into a different aspect — e.g. sampling a
    // full-screen wallpaper into a shorter shade compresses it into a smeared,
    // misaligned cast. A 1:1 slice keeps the frost uniform and aligned.
    property rect sourceRect: Qt.rect(0, 0, 0, 0)

    property real blurAmount: 1.0
    // Cap default at 24. The Qt docs document blurMax ≤ 32 as the Snapdragon
    // ceiling; the L5's etnaviv GC7000Lite is materially weaker, and the
    // wider the kernel the more fillrate it costs per vsync. blurMultiplier
    // gives back perceived strength without raising the sample radius.
    property real blurMax: MBlur.lg
    property real blurMultiplier: 1.0
    property real saturation: 0.5
    property real brightness: -0.1
    property color tint: Qt.rgba(0, 0, 0, 0.2)
    // When the backdrop is a frozen app surface (Lock screen sitting over
    // a paused Phone, QS shade pulled down over a static home) the source
    // texture does not change. Callers set live: false so the GPU samples
    // the backdrop ONCE then reuses the cached snapshot.
    property bool live: true

    visible: source !== null

    ShaderEffectSource {
        id: capture

        anchors.fill: parent
        sourceItem: root.source
        sourceRect: root.sourceRect
        live: root.live && root.visible && root.source !== null
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
        blurMultiplier: root.blurMultiplier
        saturation: root.saturation
        brightness: root.brightness
    }

    Rectangle {
        anchors.fill: parent
        color: root.tint
    }
}
