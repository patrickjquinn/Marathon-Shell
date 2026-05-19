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
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // How far past the text the halo reaches.
    property real haloMargin: 28

    // Text properties — proxied to the inner Text.
    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property alias textFormat: label.textFormat
    property alias horizontalAlignment: label.horizontalAlignment

    // The halo. SVG asset, gradient pre-baked.
    Image {
        id: halo
        x: -root.haloMargin
        y: -root.haloMargin
        width: root.width + root.haloMargin * 2
        height: root.height + root.haloMargin * 2
        source: "qrc:/qt/qml/MarathonUI/Theme/halo-teal.svg"
        fillMode: Image.PreserveAspectFit
        smooth: true
        cache: true
        z: -1
    }

    Text {
        id: label
        anchors.centerIn: parent
        // Caller sets text + font + color via the aliases above.
        // Defaults: Display 96 / weight 200 / -3 letter-spacing
        // (matches the lock clock from the DS).
        color: MColors.textPrimary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeDisplay
        font.weight: MTypography.weightExtraLight   // 200 — the comment said 200, the constant now matches
        font.letterSpacing: MTypography.trackingDisplay
        // CurveRendering (Qt 6.7+) rasterises glyph outlines analytically
        // on the GPU — strictly sharper than NativeRendering at display
        // sizes AND smooth through the opacity/scale transitions the
        // lock clock + media-mode swap go through (NativeRendering
        // snaps to integer pixels, so it shimmers during fades).
        renderType: Text.CurveRendering
        renderTypeQuality: Text.VeryHighTextRenderQuality
    }
}
