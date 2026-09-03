import "PhosphorGlyphs.js" as Phosphor
import MarathonUI.Theme
import QtQuick

// Line-icon renderer. Phosphor Light is the canonical icon family per the
// design system (ds-foundations.jsx). Callers may use Phosphor's canonical
// name (e.g. "caret-right") or one of the legacy Lucide aliases listed in
// scripts/build-phosphor-glyphs.py (e.g. "chevron-right"); both resolve to
// the same glyph.
//
// `weight` picks between Phosphor-Light (default, 1 px stroke) and
// Phosphor-Bold (status bar / dock chrome that needs to hold weight at
// very small sizes).
Text {
    id: root

    property string name: ""
    property int size: 24
    property string weight: "light"

    text: Phosphor.Glyphs[name] || ""
    font.family: weight === "bold" ? phosphorBoldFont.name : phosphorLightFont.name
    font.pixelSize: size

    color: MColors.textPrimary
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    // Decorative glyph rendered as text. Containers that wrap an Icon to make
    // it interactive (buttons, list items) carry the Accessible.name -- skip
    // so screen readers don't read the glyph codepoint.
    Accessible.ignored: true

    FontLoader {
        id: phosphorLightFont
        source: Qt.resolvedUrl("fonts/Phosphor-Light.ttf")
    }
    FontLoader {
        id: phosphorBoldFont
        source: Qt.resolvedUrl("fonts/Phosphor-Bold.ttf")
    }
}
