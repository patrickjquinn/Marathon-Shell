import QtQuick
import MarathonUI.Theme

// Display-weight text with a teal radial halo behind it.
// Used wherever a hero numeric reads against a dark surface:
//   • Lock screen clock
//   • Calculator readout
//   • Dialer number
//   • OOBE completion glyph
//
// The halo composition (teal radial fading to transparent at ~65%)
// is the design's signature — it's what makes the clock read as
// "lit", not just typed. Implemented as a static SVG asset behind
// the text rather than a MultiEffect blur, per the DS performance
// rule against persistent FBO effects.
//
// NOTE on the property model: the old `property alias font: label.font`
// caused value-type-aliasing weirdness that made Qt 6.11 silently
// substitute the variable Sora's default OS/2 weight (Regular 400) for
// every weight we asked for. We now expose the font sub-properties as
// individual properties on the component — this guarantees Qt sees
// the family + pixelSize + weight + letterSpacing as ordinary property
// bindings on a plain Text item, with no alias plumbing between them.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // How far past the text the halo reaches.
    property real haloMargin: 28

    // ── Text content ────────────────────────────────────────
    property alias text: label.text
    property alias color: label.color
    property alias textFormat: label.textFormat
    property alias horizontalAlignment: label.horizontalAlignment

    // ── Font sub-properties (NO value-type alias) ───────────
    // Default: Display 96 / weight 200 / -3 letter-spacing.
    property int pixelSize: MTypography.sizeDisplay
    property int weight: MTypography.weightExtraLight
    property real letterSpacing: MTypography.trackingDisplay

    // Hard upper bound on the rendered text width. Set by the caller
    // (lock screen passes parent.width - 2 × safeMargin). When 0 the
    // text renders unbounded — keeps backwards-compatible behaviour
    // for callers that don't care (calculator, dialer).
    property real maxWidth: 0
    // Floor for fontSizeMode shrinking: never below this px size, no
    // matter how wide the text is. Anything smaller becomes unreadable
    // at lock-screen distance.
    property int minimumPixelSize: 32

    // The halo. SVG asset, gradient pre-baked.
    Image {
        id: halo
        x: -root.haloMargin
        y: -root.haloMargin
        width: root.width + root.haloMargin * 2
        height: root.height + root.haloMargin * 2
        source: Qt.resolvedUrl("../Theme/halo-teal.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        cache: true
        z: -1
    }

    Text {
        id: label
        anchors.centerIn: parent
        // font.family must be the VARIABLE Sora (so the wght axis can
        // be instanced), and font.weight must NOT also be set: per the
        // Qt 6.7 text-improvements blog and runebook variableAxes
        // notes, setting both causes Qt to prioritise the standard
        // property and silently ignore the axis. Drive weight only
        // through variableAxes.
        color: MColors.textPrimary
        font.family: MTypography.fontFamily
        font.pixelSize: root.pixelSize
        font.variableAxes: ({
                "wght": root.weight
            })
        font.letterSpacing: root.letterSpacing
        // NativeRendering snaps to the nearest static cut of the
        // variable font (e.g. wght=100 → Thin) and renders glyphs
        // through the platform freetype hinter. QtRendering uses an
        // SDF atlas that, on Qt 6.10 + virtio-gpu software fallback,
        // overlays a ghosted secondary stroke on certain digits ("8"
        // most reliably). Trade a hair of smoothness across the
        // pixelSize animation for sharp, single-stroke glyphs.
        renderType: Text.NativeRendering

        width: root.maxWidth > 0 ? root.maxWidth : implicitWidth
        horizontalAlignment: Text.AlignHCenter
        // HorizontalFit shrinks pixelSize down to root.minimumPixelSize
        // when the text wouldn't otherwise fit width — keeps the clock
        // inside the viewport on high-DPI panels where the design-px
        // size × scaleFactor would overflow.
        fontSizeMode: root.maxWidth > 0 ? Text.HorizontalFit : Text.FixedSize
        minimumPixelSize: root.minimumPixelSize
    }
}
