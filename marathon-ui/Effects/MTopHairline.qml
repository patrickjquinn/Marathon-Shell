import QtQuick
import QtQuick.Shapes

// DS "lit from above" hairline (ds-foundations.jsx / app-icons.jsx).
//
// Renders a 1 px stroke along the TOP arc of a rounded-rectangle
// container, tracing the squircle's left-top corner, the top edge,
// and the right-top corner. Use this instead of a flat horizontal
// `Rectangle { anchors.top; height: 1 }` — that variant draws a
// straight line that extends past the rounded corners and visibly
// breaks the squircle silhouette.
//
// Sizes itself to the parent. Set `radius` to match the parent's
// corner radius. `inset` is how far inside the parent's edge the
// hairline sits (default 1, so it lands just inside a 1 px outer
// ring drawn at the very edge).
//
// Default color is white-15 to match the JSX
//   inset 0 1px 0 rgba(255,255,255,0.15)
// box-shadow used on every Marathon icon / card / button / toggle.
Item {
    id: root

    property color color: Qt.rgba(1, 1, 1, 0.15)
    property real radius: 14
    property real lineWidth: 1
    property real inset: 1

    anchors.fill: parent

    Shape {
        anchors.fill: parent
        antialiasing: true
        // CurveRenderer does GPU-side analytical AA per fragment — strictly
        // sharper than GeometryRenderer + layer.samples MSAA for curves,
        // and avoids the FBO round-trip the `layer.enabled` path forced.
        // This is the single biggest crispness win for every squircle
        // hairline in the system (cards, buttons, toggles, app icons,
        // sheets, modals).
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.color
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            // Start at the bottom of the top-left arc.
            startX: root.inset
            startY: root.radius + root.inset

            // Top-left arc — sweeps clockwise to the top edge.
            PathArc {
                x: root.radius + root.inset
                y: root.inset
                radiusX: root.radius - root.inset
                radiusY: root.radius - root.inset
                direction: PathArc.Clockwise
            }

            // Straight top edge.
            PathLine {
                x: root.width - root.radius - root.inset
                y: root.inset
            }

            // Top-right arc — sweeps clockwise into the right edge.
            PathArc {
                x: root.width - root.inset
                y: root.radius + root.inset
                radiusX: root.radius - root.inset
                radiusY: root.radius - root.inset
                direction: PathArc.Clockwise
            }
        }
    }
}
