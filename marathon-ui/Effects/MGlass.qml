import QtQuick
import QtQuick.Effects
import MarathonUI.Theme

// Marathon DS · Glass (Marathon QML Guide §05 · ds-components.jsx:DSGlass).
//
// Backdrop blur primitive — status bar, top bar, tab bar, dock, NowBar,
// system HUD, sheets. Pattern: ShaderEffectSource snapshots the backdrop,
// MultiEffect blurs the snapshot, a tint Rectangle paints on top.
//
// autoPaddingEnabled MUST be false for full-bleed chrome — otherwise
// MultiEffect grows the effect bounds beyond the host item, leaving a
// halo at the screen edge.
//
// Performance contract per the guide:
//   - One MGlass per visible layer. If a sheet sits over the top bar,
//     the SHEET's MGlass snapshots the WHOLE composited screen — don't
//     stack two MGlass on top of each other.
//   - Cap blurMaxRadius ≤ 32 on Snapdragon-class. The Qt blog confirms
//     blurMultiplier is cheaper than raising blurMax.
//   - Set live:false on the snapshot when the backdrop isn't animating
//     (collapsed sheets, lock screens with static wallpaper).
Item {
    id: root

    property Item sourceItem: null

    property real blurStrength: 1.0

    property real blurMaxRadius: 32

    property real blurMultiplier: 1.0

    property color tint: Qt.rgba(0.05, 0.05, 0.055, 0.78)

    property color borderColor: Qt.rgba(1, 1, 1, 0.06)

    property bool topHairline: true

    // Optional colour-grading on the blurred snapshot. 1.0 / 0.0 are
    // neutral. Lock-screen / PIN-screen blurs lean on a desaturated and
    // slightly darker backdrop so foreground chrome reads clearly
    // against busy wallpapers — set saturation ~0.3 and brightness ~-0.2
    // for that treatment.
    property real saturation: 1.0
    property real brightness: 0.0

    // Snapshot only the chrome region. Smaller rect = cheaper blur,
    // especially on Pinephone-class hardware. Bind to the parent's
    // bounds by default; override at the call site if the host item is
    // larger than the visible glass area (e.g. an animated sheet whose
    // host extends off-screen).
    property rect sourceRect: Qt.rect(x, y, width, height)

    // Default false: most chrome (status bar, nav bar, dock, tab bar) sits
    // over a backdrop that is static at idle. Live-sampling every vsync
    // burns render-thread CPU for no visual difference. Call sites whose
    // backdrop genuinely animates (a sheet sliding over a video) opt in
    // with `live: true`.
    property bool live: false

    ShaderEffectSource {
        id: snap
        anchors.fill: parent
        sourceItem: root.sourceItem
        sourceRect: root.sourceRect
        visible: false
        live: root.live
        hideSource: false
    }

    MultiEffect {
        anchors.fill: parent
        source: snap
        blurEnabled: true
        blur: root.blurStrength
        blurMax: root.blurMaxRadius
        blurMultiplier: root.blurMultiplier
        saturation: root.saturation
        brightness: root.brightness
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: root.tint
        border.width: 1
        border.color: root.borderColor
    }

    Rectangle {
        visible: root.topHairline
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(1, 1, 1, 0.04)
    }
}
