import "LucideGlyphs.js" as Lucide
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

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

    FontLoader {
        id: lucideFont

        source: Qt.resolvedUrl("fonts/lucide.ttf")
    }
}
