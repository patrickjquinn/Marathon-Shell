// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// VariantInterpolator (Sailfish.Silica.private): `value` between `from`
// and `to` at `progress` (0..1), for numbers and colours (Silica's BSD
// private/TabButton.qml). Keel's stand-in.
import QtQml

QtObject {
    property var from
    property var to
    property real progress

    readonly property var value: {
        var p = Math.max(0, Math.min(1, progress))
        if (typeof from === "number" && typeof to === "number")
            return from + (to - from) * p
        if (from === undefined || to === undefined)
            return p < 0.5 ? from : to
        var a = Qt.tint(from, "transparent")
        var b = Qt.tint(to, "transparent")
        return Qt.rgba(a.r + (b.r - a.r) * p, a.g + (b.g - a.g) * p,
                       a.b + (b.b - a.b) * p, a.a + (b.a - a.a) * p)
    }
}
