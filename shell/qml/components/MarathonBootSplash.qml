import QtQuick

// Plymouth's boot splash (marathon.script) at Plymouth's device scale: the same
// images at the same pixels, so the PIN pad and the shell take over its frame
// without a visible change. Positions are the script's, in its units.
Item {
    id: root

    // PlymouthScale (main.cpp): 1, or 2 on a dense panel.
    property int deviceScale: 1
    // The wordmark and the progress bar.
    property real chromeOpacity: 1
    property real logoOpacity: 1
    property real progress: 0
    // 0 at the script's place, 1 at liftTarget (this item's pixels).
    property real lift: 0
    property rect liftTarget

    readonly property string theme: "file:///usr/share/plymouth/themes/marathon/"

    Item {
        id: plymouth

        width: root.width / root.deviceScale
        height: root.height / root.deviceScale
        scale: root.deviceScale
        transformOrigin: Item.TopLeft

        Image {
            id: logo

            readonly property real splashX: Math.floor(plymouth.width / 2 - sourceSize.width / 2)
            readonly property real splashY: Math.floor(plymouth.height / 2 - sourceSize.height / 2 - 24)

            source: root.theme + "marathon-logo.png"
            opacity: root.logoOpacity
            x: splashX + (root.liftTarget.x / root.deviceScale - splashX) * root.lift
            y: splashY + (root.liftTarget.y / root.deviceScale - splashY) * root.lift
            width: sourceSize.width + (root.liftTarget.width / root.deviceScale - sourceSize.width) * root.lift
            height: sourceSize.height + (root.liftTarget.height / root.deviceScale - sourceSize.height) * root.lift
        }
        Text {
            // Plymouth's "Sans 14" in its font (Plymouth.ttf, Sora) through
            // FreeType: these measure the same glyph boxes on the panel.
            text: "M A R A T H O N" // i18n: literal
            color: "white"
            font.family: "Sora"
            font.pixelSize: 18
            font.letterSpacing: 0.15
            opacity: root.chromeOpacity
            x: Math.floor(plymouth.width / 2 - width / 2)
            y: Math.floor(plymouth.height / 2 + logo.sourceSize.height / 2 - 24) + 1
        }
        Image {
            id: track

            source: root.theme + "progress-track.png"
            opacity: root.chromeOpacity
            x: Math.floor(plymouth.width / 2 - width / 2)
            y: plymouth.height - 110
        }
        Image {
            source: root.theme + "progress-fill.png"
            opacity: root.chromeOpacity
            visible: root.progress > 0
            x: track.x
            y: track.y
            width: Math.round(track.width * root.progress)
            height: track.height
            fillMode: Image.Stretch
        }
    }
}
