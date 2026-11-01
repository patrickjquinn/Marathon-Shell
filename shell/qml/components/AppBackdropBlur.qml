import MarathonOS.Shell
import QtQuick
import QtQuick.Effects

// Frosted glass over the layers behind the chrome: the app's surface, or the
// wallpaper and home screen. Marathon samples them inline, where another
// Wayland shell would need a screen copy across IPC per frame.
//
// The layers are captured, bottom to top, at a quarter of this item's size
// and blurred at that size, then scaled up: a blur loses the detail the small
// texture would. They are halved twice, each step averaging 2x2 pixels: drawn
// straight at a quarter, a pixel took one sample of its 4x4 block, and text
// showed through the frost in streaks. A live capture redraws only when a
// layer changes, and only while this item is visible (coding-rules C8).
Item {
    id: root

    // Bottom to top. `source` is the one-layer form.
    property list<Item> sources
    property Item source

    // The region of the layers behind this item, in their coordinates, the
    // same size as this item so the frost stays aligned; empty is all of it.
    property rect sourceRect: Qt.rect(0, 0, 0, 0)

    property real blurAmount: 1.0
    // In the small texture's pixels, so one step frosts four times as wide.
    property real blurMax: MBlur.lg
    // Over 1 the blur skips pixels and leaves ghost copies (Qt's docs).
    property real blurMultiplier: 1.0
    property real saturation: 0.5
    property real brightness: -0.1
    property color tint: Qt.rgba(0, 0, 0, 0.2)
    // False when the layers cannot change underneath (a frozen app under the
    // lock screen): they are captured and blurred once.
    property bool live: true

    readonly property list<Item> layers: sources.length > 0 ? sources : (source ? [source] : [])

    visible: layers.length > 0

    Item {
        id: half

        width: Math.max(1, Math.ceil(root.width / 2))
        height: Math.max(1, Math.ceil(root.height / 2))
        visible: false

        Repeater {
            model: root.layers

            ShaderEffectSource {
                required property Item modelData

                anchors.fill: parent
                sourceItem: modelData
                sourceRect: root.sourceRect
                textureSize: Qt.size(half.width, half.height)
                live: root.live && root.visible
                recursive: false
                // RGBA16F avoids dark fringes round bright pixels; etnaviv
                // cannot render to it, so it follows MARATHON_GPU_HDR.
                format: Constants.gpuHdr ? ShaderEffectSource.RGBA16F : ShaderEffectSource.RGBA
                smooth: true
            }
        }
    }

    ShaderEffectSource {
        id: small

        width: Math.max(1, Math.ceil(half.width / 2))
        height: Math.max(1, Math.ceil(half.height / 2))
        sourceItem: half
        textureSize: Qt.size(width, height)
        live: root.live && root.visible
        format: Constants.gpuHdr ? ShaderEffectSource.RGBA16F : ShaderEffectSource.RGBA
        smooth: true
        visible: false
    }

    // Blurred at the small size into a layer, which is scaled up filtered.
    Item {
        width: small.width
        height: small.height
        scale: 4
        transformOrigin: Item.TopLeft
        layer.enabled: true
        layer.smooth: true

        MultiEffect {
            anchors.fill: parent
            source: small
            autoPaddingEnabled: false
            blurEnabled: true
            blur: root.blurAmount
            blurMax: root.blurMax
            blurMultiplier: root.blurMultiplier
            saturation: root.saturation
            brightness: root.brightness
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.tint
    }
}
