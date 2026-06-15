import MarathonUI.Theme
import QtQuick
import QtQuick.Shapes

// Marathon brand mark — canonical lockup from
// docs/redesign/marathonos/project/design-system/ds-foundations.jsx.
//
// A teal-gradient disc (#1de9b6 → #00bfa5) carrying a black "M" path
// centred, optional "marathon" lowercase tracked-caps label below,
// optional soft teal halo. THIS is the logo; no other variants.
//
// Proportions match the BootSplash reference: disc = 43% of canvas
// size; M path inside = 58% of disc; halo blur = 42% of disc; word
// = 6.3% of canvas with 2.7% letter-spacing.
//
// Vector throughout — same XML at 28 dp watermark and 320 dp hero.
Item {
    id: root

    property int size: Math.round(220 * Constants.scaleFactor)
    property bool showLabel: true
    property bool monochrome: false
    property bool glow: true

    readonly property int discSize: Math.round(size * 0.43)
    readonly property int mSize: Math.round(discSize * 0.58)
    readonly property int haloRadius: Math.round(discSize * 0.42)
    readonly property int wordSize: Math.max(9, Math.round(size * 0.063))
    readonly property real wordTracking: Math.max(2, Math.round(size * 0.027))

    implicitWidth: size
    implicitHeight: discSize + (showLabel ? wordSize + Math.round(size * 0.10) : 0)

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(root.size * 0.10)

        // Halo + disc + M.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.discSize
            height: root.discSize

            // Soft teal halo behind the disc — concentric Rectangles
            // with decreasing opacity simulate the JSX boxShadow blur
            // without pulling in MultiEffect (heavy on the Pi 5 GPU).
            // Three rings = three stops of falloff approximating the
            // 0..0.45 opacity gradient. Each ring is radius=width/2 so
            // it stays circular at any size.
            Repeater {
                model: root.glow && !root.monochrome ? 3 : 0

                Rectangle {
                    required property int index

                    anchors.centerIn: parent
                    width: parent.width + Math.round(root.haloRadius * (0.4 + index * 0.4))
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.round(root.haloRadius * 0.35)
                    border.color: Qt.rgba(0.114, 0.749, 0.647, 0.22 - index * 0.07)
                    antialiasing: true
                    z: -1
                }
            }

            Rectangle {
                id: disc

                anchors.fill: parent
                radius: width / 2
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                antialiasing: true

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#1de9b6"
                    }
                    GradientStop {
                        position: 1
                        color: root.monochrome ? "#1de9b6" : "#00bfa5"
                    }
                }

                // Black M path. viewBox 0..56 per JSX spec. ShapePath has
                // no `scale` property in QtQuick.Shapes 6.x — using it
                // silently does nothing, leaving the path at its native
                // (10,14)–(46,44) pixel coords in the upper-left of the
                // Shape. Use Item.scale on the Shape itself with a fixed
                // 56×56 box; QML's Item transform centres the scaled
                // box on the same anchors point.
                Shape {
                    anchors.centerIn: parent
                    width: 56
                    height: 56
                    scale: root.mSize / 56
                    antialiasing: true
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeWidth: -1
                        fillColor: "#000"
                        PathSvg {
                            path: "M10 44V14h6l12 18 12-18h6v30h-6V24L28 40 16 24v20z"
                        }
                    }
                }
            }
        }

        // "marathon" word — Sora 300, tracked, lowercase per JSX comment
        // ("letter-spaced caps below" — JSX renders uppercase via
        // text-transform; we match by setting font.capitalization).
        Text {
            visible: root.showLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: "marathon"
            color: root.monochrome ? "#040404" : "#fff"
            font.family: MTypography.fontFamily
            font.pixelSize: root.wordSize
            font.weight: Font.Light
            font.letterSpacing: root.wordTracking
            font.capitalization: Font.AllUppercase
            renderType: Text.QtRendering
        }
    }
}
