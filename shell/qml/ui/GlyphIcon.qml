import "PhosphorGlyphs.js" as Phosphor
import MarathonOS.Shell
import QtQuick

// Line-icon renderer. Phosphor Thin: its stroke is 1/32 of the em, the same
// as Sailfish's own icon-m-* set. Callers may use Phosphor's canonical
// name (e.g. "caret-right") or one of the legacy Lucide aliases listed in
// scripts/build-phosphor-glyphs.py (e.g. "chevron-right"); both resolve to
// the same glyph.
//
// `weight` picks between Phosphor-Thin (default) and
// Phosphor-Bold (status bar / dock chrome that needs to hold weight at
// very small sizes).
Text {
    id: root

    property string name: ""
    property int size: 24
    property string weight: "thin"

    text: Phosphor.Glyphs[name] || ""
    font.family: weight === "bold" ? MTypography.iconFontBold : MTypography.iconFontThin
    font.pixelSize: size

    color: MColors.textPrimary
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    // Decorative glyph rendered as text. Containers that wrap an Icon to make
    // it interactive (buttons, list items) carry the Accessible.name -- skip
    // so screen readers don't read the glyph codepoint.
    Accessible.ignored: true
}
