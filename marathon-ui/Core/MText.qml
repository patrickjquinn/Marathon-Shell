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

    // Value-gated mirror of the weight. Binding font.family directly to
    // root.font.weight was a binding loop: font.family and font.weight are
    // both sub-properties of the `font` value-type group, so *writing*
    // font.family re-fired the whole group's change signal, re-evaluating
    // the family binding, re-writing font.family... Qt detects and breaks
    // it, but it logs a warning on every MText instance. Routing through a
    // plain int makes the family binding depend on the weight *value*: when
    // the group re-notifies but the weight is unchanged, this int doesn't
    // emit changed(), so the family binding doesn't re-run. Callsites still
    // set font.weight as before — the public contract is unchanged.
    readonly property int _weightForFamily: font.weight

    // Per-cut family — see MTypography for the rationale. Without this
    // every callsite that asks for ExtraLight / Light / Thin Sora got
    // the OS/2 default Regular cut due to Qt 6.11 variable-font axis
    // handling. fontFamilyForWeight selects the matching static face.
    font.family: MTypography.fontFamilyForWeight(root._weightForFamily)
    font.pixelSize: MTypography.sizeBody
    font.hintingPreference: Font.PreferNoHinting
    font.kerning: true

    renderType: Text.QtRendering

    // font.features is QHash<QString, quint32> on Qt 6.7+; pass an object
    // literal in parens (the parens stop QML from treating the braces as a
    // binding block). The array-of-strings form used to be here silently
    // assigned a QVariantList where a QVariantMap was expected — qmllint
    // flagged the type mismatch and the feature didn't take.
    font.features: tnum ? ({
            "tnum": 1
        }) : ({})
}
