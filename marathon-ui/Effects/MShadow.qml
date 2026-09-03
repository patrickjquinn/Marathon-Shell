import QtQuick
import QtQuick.Effects
import MarathonUI.Theme

// Marathon DS · Shadow (Marathon QML Guide §04 · ds-components.jsx:DSShadows).
//
// Version-agnostic shadow wrapper. Marathon's Qt baseline is 6.7 LTS;
// every component renders through this primitive so a later move to
// RectangularShadow (Qt 6.9+, shader-based, no source texture, ~4x
// faster) only changes ONE file.
//
// API surface intentionally matches CSS box-shadow semantics:
//   shadowColor   ← box-shadow color
//   blur          ← box-shadow blur-radius (CSS px)
//   offset        ← box-shadow x/y (CSS px)
//   radius        ← border-radius of the source item (for shape match)
//
// The CSS→Qt blur conversion (multiplier 1.2× per the Qt blog) is
// applied inside; call sites pass the same value they'd use in CSS.
//
// Performance contract:
//   - shadowBlur is normalised 0..1 in MultiEffect — we clamp the
//     converted radius accordingly.
//   - Cap blur ≤ 24 (CSS px). Beyond that the box-blur kernel becomes
//     visibly tiled and GPU cost scales quadratically.
//   - autoPaddingEnabled grows the host bounds; usually right for
//     drop shadows, set autoPadding:false for full-bleed chrome where
//     the shadow shouldn't bleed past the chrome edge.
Item {
    id: root

    property Item source: null

    property color shadowColor: Qt.rgba(0, 0, 0, 0.6)

    property real blur: 12

    property point offset: Qt.point(0, 6)

    property real radius: MRadius.md

    property bool autoPadding: true

    MultiEffect {
        anchors.fill: parent
        source: root.source
        shadowEnabled: true
        shadowColor: root.shadowColor
        // CSS px → MultiEffect normalised 0..1: empirical 1.2× factor
        // matches Marathon's box-shadow visual exactly (per the QML
        // Guide §08 Gap 4). Clamp at 1.0 so callers passing huge
        // blur values don't break the shader.
        shadowBlur: Math.min(1.0, (root.blur * 1.2) / 64)
        shadowVerticalOffset: root.offset.y
        shadowHorizontalOffset: root.offset.x
        shadowOpacity: 1.0
        autoPaddingEnabled: root.autoPadding
    }
}
