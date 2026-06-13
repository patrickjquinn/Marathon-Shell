import QtQuick
import MarathonUI.Theme

// Marathon DS · Text base (Marathon QML Guide §08 Gap 3 ·
// ds-qml-guide.jsx:DSQMLParity).
//
// Every Marathon Text element should extend MText, not Qt's bare Text.
// Two settings are non-negotiable for parity with the web preview:
//
//   1. font.hintingPreference = PreferNoHinting
//      Qt's default platform hinting bolds Sora at weight 200 noticeably.
//      Browsers render Sora 200 with anti-aliasing only; opting out of
//      hinting matches that exactly.
//
//   2. renderType = Text.QtRendering
//      QtRendering preserves the variable-font weight axis. NativeRendering
//      flattens to the nearest static cut, which kills Sora 200 (it
//      snaps to 300 or 400 depending on what fontconfig has cached).
//      The cost is a single distance-field texture upload — sustainable
//      even on Pinephone-class GPUs.
//
// Tabular numerics are opt-in via the `tnum` property. Set true on any
// Text that shows changing numbers (timers, prices, percentages, list
// values) so digits don't dance during transitions.
Text {
    id: root

    property bool tnum: false

    color: MColors.textPrimary
    font.family: MTypography.fontFamily
    font.pixelSize: MTypography.sizeBody
    font.hintingPreference: Font.PreferNoHinting
    font.kerning: true

    // Body text via NativeRendering routes through fontconfig, where
    // each Sora named instance is registered with its real CSS weight
    // (Thin=100 → fc weight=0 → "Sora Thin" face). The QtRendering +
    // font.weight path empirically rounds 100/200/300 up to Regular
    // for this variable font on Qt 6.11 — pixel-verified against
    // fontTools-instanced reference renders. NativeRendering loses the
    // SDF smoothness during scale/opacity transitions, but Marathon's
    // body text doesn't animate, and Sora-at-weight beats SDF-blur
    // every time.
    renderType: Text.NativeRendering

    // Array-of-strings form per the guide §08 Gap 7 — works on Qt 6.6.0
    // (some builds reject the object-literal form), and 6.6.1+. Safer
    // baseline given Marathon's 6.7 LTS target with downstream packagers
    // that may patch back.
    font.features: tnum ? ["tnum on"] : []
}
