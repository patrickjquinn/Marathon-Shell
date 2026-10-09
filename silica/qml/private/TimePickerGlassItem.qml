// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TimePickerGlassItem (private): the indicator dot that circles a
// TimePicker track. Silica's own file is not open (no BSD header in
// sailfishsilica-qt5 1.2.156); this is Keel's clean-room stand-in with the
// properties Silica's BSD TimePicker.qml sets: `value` (in steps of
// `stepCount` per turn), `rotationRadius`, `velocity`, `highlighted`,
// `moving`, `animationEnabled`.
import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0

Item {
    id: root

    property real value
    property int stepCount: 60
    property real rotationRadius
    property real velocity: 30
    property bool highlighted
    property bool moving
    property bool animationEnabled: true

    width: 2 * rotationRadius
    height: width
    rotation: stepCount > 0 ? 360 * value / stepCount : 0
    Behavior on rotation {
        enabled: root.animationEnabled && !root.moving
        RotationAnimation { duration: 200; direction: RotationAnimation.Shortest; easing.type: Easing.InOutQuad }
    }

    GlassItem {
        // Measured: the glow is about 1.4 times a switch's (tests/screenshots/reference/SOURCES.md).
        width: Math.round(1.4 * Theme.itemSizeExtraSmall)
        height: width
        x: (root.width - width) / 2
        y: -height / 2
        color: root.highlighted ? Theme.highlightColor : Theme.lightPrimaryColor
        radius: 0.25
        falloffRadius: 0.2
    }
}
