import QtQuick
import MarathonUI.Theme

// Marathon DS · Glow (Marathon QML Guide §04 — "teal halo under a
// primary CTA"). Convenience wrapper over MShadow that paints the
// shadow in teal with zero offset — the canonical halo treatment for
// primary buttons, focus rings, active toggles, the NowBar music chip.
MShadow {
    shadowColor: MColors.tealHalo
    blur: 16
    offset: Qt.point(0, 0)
    autoPadding: true
}
