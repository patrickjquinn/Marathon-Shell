import QtQuick
import QtQuick.Effects
import MarathonUI.Theme

import "LucideGlyphs.js" as Lucide

Text {
    id: root
    property string name: ""
    property int size: 24

    FontLoader {
        id: lucideFont
        source: "qrc:/fonts/lucide.ttf"
    }

    // Map icon name to glyph character
    text: Lucide.Glyphs[name] || ""

    font.family: lucideFont.name
    font.pixelSize: size

    // Default color (can be overridden)
    color: MColors.textPrimary

    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    // Performance optimization: Text is much lighter than Image+Shader
    // No layer.enabled needed for coloring!
}
