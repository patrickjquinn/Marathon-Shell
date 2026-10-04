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
    // especially on Pinephone-class hardware. Defaults to the glass's own
    // bounds in sourceItem's coordinates; override at the call site if the
    // host item is larger than the visible glass area (e.g. an animated
    // sheet whose host extends off-screen).
    property rect sourceRect: _backdropRect

    // The glass's x/y are in its parent's coordinates, which for a dialog
    // or sheet panel are not sourceItem's, so the snapshot showed the top
    // of the page instead of what is behind the panel. Sum the offsets up
    // to sourceItem rather than mapToItem(): that is tracked, so a panel
    // that slides is followed, and it ignores the panel's scale-in, which
    // would otherwise re-capture a backdrop that now holds the panel.
    readonly property rect _backdropRect: {
        let dx = 0;
        let dy = 0;
        let p = root;
        for (; p && p !== root.sourceItem; p = p.parent) {
            dx += p.x;
            dy += p.y;
        }
        if (!root.sourceItem || !p) {
            const pos = root.sourceItem ? root.mapToItem(root.sourceItem, 0, 0) : Qt.point(x, y);
            return Qt.rect(pos.x, pos.y, width, height);
        }
        return Qt.rect(dx, dy, width, height);
    }

    // Default false: most chrome (status bar, nav bar, dock, tab bar) sits
    // over a backdrop that is static at idle. Live-sampling every vsync
    // burns render-thread CPU for no visual difference. Call sites whose
    // backdrop genuinely animates (a sheet sliding over a video) opt in
    // with `live: true`.
    property bool live: false

    // ── Reduce-blur path ─────────────────────────────────────
    // When MMotion.reduceBlur is true, skip the ShaderEffectSource +
    // MultiEffect pipeline entirely — that's a ~per-glass-surface GPU
    // pass we don't want to pay on etnaviv GLES2 when the user has
    // opted out. The tint Rectangle becomes the entire chrome surface,
    // so its color needs to be opaque (alpha 1.0); we force it from
    // the configured tint so the colour identity is preserved.
    readonly property bool _reduceBlur: MMotion.reduceBlur
    readonly property color _opaqueTint: Qt.rgba(tint.r, tint.g, tint.b, 1.0)

    // Sheets, modals and dialogs pass their own parent as the backdrop, and
    // that parent contains this glass. Qt renders such a self-containing
    // source as garbage unless the capture is marked recursive.
    readonly property bool _sourceContainsSelf: {
        for (let p = root.parent; p; p = p.parent) {
            if (p === root.sourceItem)
                return true;
        }
        return false;
    }

    ShaderEffectSource {
        id: snap
        anchors.fill: parent
        sourceItem: root.sourceItem
        recursive: root._sourceContainsSelf
        sourceRect: root.sourceRect
        visible: false
        live: root.live && !root._reduceBlur
        hideSource: false
    }

    MultiEffect {
        anchors.fill: parent
        source: snap
        visible: !root._reduceBlur
        blurEnabled: !root._reduceBlur
        blur: root.blurStrength
        blurMax: root.blurMaxRadius
        blurMultiplier: root.blurMultiplier
        saturation: root.saturation
        brightness: root.brightness
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: root._reduceBlur ? root._opaqueTint : root.tint
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
