import "LucideGlyphs.js" as Lucide
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

Text {
    // Performance optimization: Text is much lighter than Image+Shader
    // No layer.enabled needed for coloring!

    id: root

    property string name: ""
    property int size: 24

    // Map icon name to glyph character
    text: Lucide.Glyphs[name] || ""
    font.family: lucideFont.name
    font.pixelSize: size
    // Default color (can be overridden)
    color: MColors.textPrimary
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    FontLoader {
        id: lucideFont

        // Keep this module self-contained: the Lucide font is packaged as a MarathonUI.Core resource.
        // Using Qt.resolvedUrl makes it work from any process (shell or isolated runner).
        source: Qt.resolvedUrl("fonts/lucide.ttf")
    }
}
