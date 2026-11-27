import QtQuick

// Plymouth's boot splash (marathon.script) at Plymouth's device scale: the same
// images at the same pixels, so the shell takes over its frame without a
// visible change. Positions are the script's, in its units.
Item {
    id: root

    // PlymouthScale (main.cpp): 1, or 2 on a dense panel.
    property int deviceScale: 1
    property real progress: 0

    readonly property string theme: "file:///usr/share/plymouth/themes/marathon/"

    Item {
        id: plymouth

        width: root.width / root.deviceScale
        height: root.height / root.deviceScale
        scale: root.deviceScale
        transformOrigin: Item.TopLeft

        Image {
            id: logo

            source: root.theme + "marathon-logo.png"
            x: Math.floor(plymouth.width / 2 - width / 2)
            y: Math.floor(plymouth.height / 2 - height / 2 - 24)
        }
        Text {
            // Plymouth's "Sans 14" in its font (Plymouth.ttf, Sora) through
            // FreeType: these measure the same glyph boxes on the panel.
            text: "M A R A T H O N" // i18n: literal
            color: "white"
            font.family: "Sora"
            font.pixelSize: 18
            font.letterSpacing: 0.15
            x: Math.floor(plymouth.width / 2 - width / 2)
            y: Math.floor(plymouth.height / 2 + logo.height / 2 - 24) + 1
        }
        Image {
            id: track

            source: root.theme + "progress-track.png"
            x: Math.floor(plymouth.width / 2 - width / 2)
            y: plymouth.height - 110
        }
        Image {
            source: root.theme + "progress-fill.png"
            visible: root.progress > 0
            x: track.x
            y: track.y
            width: Math.round(track.width * root.progress)
            height: track.height
            fillMode: Image.Stretch
        }
    }
}
