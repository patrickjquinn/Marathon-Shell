import "PhosphorGlyphs.js" as Phosphor
import MarathonOS.Shell
import QtQuick

// A notification's icon: its image (data URL, path or URL) or a glyph or
// theme icon by name; else its freedesktop category's glyph, else fallback.
Item {
    id: root

    property string source: ""
    property string category: ""
    property string fallback: "bell"
    property real size: 24
    property color color: MColors.textPrimary
    readonly property bool hasImage: image.status === Image.Ready
    readonly property bool isGlyph: !!Phosphor.Glyphs[source]
    readonly property var categoryGlyphs: ({
            "call": "phone",
            "device": "device-mobile",
            "email": "mail",
            "im": "chat-circle",
            "network": "wifi-high",
            "presence": "user",
            "transfer": "download"
        })
    readonly property string glyph: isGlyph ? source : categoryGlyphs[category.split(".")[0]] || fallback

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image

        anchors.fill: parent
        source: root.source === "" || root.isGlyph ? "" : root.source.startsWith("/") ? "file://" + root.source : root.source.indexOf(":") > 0 ? root.source : "image://theme/" + root.source
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: root.hasImage
    }

    GlyphIcon {
        anchors.centerIn: parent
        visible: !root.hasImage
        name: root.glyph
        size: root.size
        color: root.color
    }
}
