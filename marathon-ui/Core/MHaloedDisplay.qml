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
        // The Theme module qrc resource. Use the full URL so resolution
        // works whether or not the caller has already imported
        // MarathonUI.Theme — the hardcoded qrc path resolves through the
        // global Qt resource system once any module has loaded the
        // Theme resource bundle. (Previous failure mode: Image opened
        // before Theme.qmldir was processed → resource not yet
        // registered → "Cannot open: qrc:..." warning. Use the
        // Qt.resolvedUrl pointing into the sibling Theme/ directory
        // instead — Qt's QQmlEngine handles the cross-module ref.)
        source: Qt.resolvedUrl("../Theme/halo-teal.svg")
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
        font.weight: MTypography.weightExtraLight   // 200 default
        font.letterSpacing: MTypography.trackingDisplay
        // NativeRendering routes the glyph lookup through fontconfig.
        // Fontconfig sees Sora's variable-font named instances as
        // discrete weighted faces (verified with fc-list :family=Sora →
        // Thin / ExtraLight / Light / Regular / SemiBold / Bold /
        // ExtraBold). The QtRendering path silently ignored font.weight
        // AND font.variableAxes for this font in Qt 6.11 (pixel-verified:
        // clock matched Regular when asked for Thin), so we let
        // fontconfig do the matching instead.
        renderType: Text.NativeRendering
    }

    // Force the family to the named-instance fullname matching the
    // requested weight, bypassing the `font` alias from the caller.
    // The inline `font.family` binding in the Text item above is
    // overridden whenever the outer caller writes
    // `MHaloedDisplay { font.family: ... }` (alias semantics), so we
    // use Binding{} which wins over alias-driven assignment. Without
    // this, the family stays at the variable-font's default record
    // and font.weight is ignored — see the comment above.
    Binding {
        target: label
        property: "font.family"
        value: label.font.weight <= 100 ? "Sora Thin" : label.font.weight <= 200 ? "Sora ExtraLight" : label.font.weight <= 300 ? "Sora Light" : label.font.weight <= 400 ? "Sora Regular" : label.font.weight <= 600 ? "Sora SemiBold" : label.font.weight <= 700 ? "Sora Bold" : "Sora ExtraBold"
    }
}
