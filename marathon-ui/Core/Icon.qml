import "LucideGlyphs.js" as Lucide
import MarathonUI.Theme
import QtQuick

Text {
    id: root

    property string name: ""
    property int size: 24

    text: Lucide.Glyphs[name] || ""
    font.family: lucideFont.name
    font.pixelSize: size

    color: MColors.textPrimary
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    // Decorative glyph rendered as text. Containers that wrap an Icon to make
    // it interactive (buttons, list items) carry the Accessible.name -- skip
    // so screen readers don't read the glyph codepoint.
    Accessible.ignored: true

    FontLoader {
        id: lucideFont

        source: Qt.resolvedUrl("fonts/lucide.ttf")
    }
}
