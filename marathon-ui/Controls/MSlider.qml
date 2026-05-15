import QtQuick
import QtQuick.Effects
import MarathonUI.Theme
import MarathonOS.Shell

// Marathon DS · Slider (ds-components.jsx:DSInputs · "Slider").
//
// 4 px track in w-08 background (radius 2). Teal-gradient fill from
// the left edge to the current value. 16 × 16 white thumb with a
// large soft teal-halo glow per JSX brightness slider reference —
// the halo is ~28-32 px wide and feathered out via MultiEffect
// blur, not a hard ring.
//
// Track endpoints are pill-radius so the fill segment never reads as
// a clipped rectangle, matching the slider in Settings → Brightness.
Item {
    id: root

    property real value: 0.5
    property real from: 0.0
    property real to: 1.0
    property bool disabled: false

    signal moved
    signal released

    readonly property alias pressed: handleArea.pressed

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real trackHeight: Math.max(1, Math.round(4 * scaleFactor))
    readonly property real handleSize: Math.round(16 * scaleFactor)

    implicitWidth: parent ? parent.width : 240
    implicitHeight: Math.round(24 * scaleFactor)

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: trackHeight
        radius: height / 2          // pill end-caps
        color: MColors.whiteOverlay08

        // Fill segment — teal-gradient from left to value.
        Rectangle {
            width: Math.max(parent.height, (root.value - root.from) / (root.to - root.from) * parent.width)
            height: parent.height
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: MColors.marathonTealDark
                }
                GradientStop {
                    position: 1.0
                    color: MColors.marathonTealBright
                }
            }
        }
    }

    // Halo source disc — sits behind the thumb, larger than it, fed
    // through MultiEffect blur to produce a real soft glow rather than
    // a hard ring. Only rendered while not disabled (no halo on a
    // dimmed slider).
    Rectangle {
        id: haloSource
        visible: !root.disabled
        x: handle.x + handle.width / 2 - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: handle.width + 18
        height: handle.height + 18
        radius: width / 2
        color: MColors.marathonTealBright
        opacity: handleArea.pressed ? 0.75 : 0.55
        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
            }
        }
        z: -1

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 24
            blurMultiplier: 1.2
        }
    }

    Rectangle {
        id: handle
        x: (root.value - root.from) / (root.to - root.from) * (parent.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: handleSize
        height: handleSize
        radius: width / 2
        color: "#FFFFFF"

        // Subtle 1 px inner stroke so the thumb reads cleanly on the
        // teal fill segment.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.18)
        }

        scale: handleArea.pressed ? 1.15 : 1.0
        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springLight
                damping: MMotion.dampingLight
                epsilon: MMotion.epsilon
            }
        }

        Behavior on x {
            enabled: !handleArea.drag.active
            NumberAnimation {
                duration: MMotion.quick
            }
        }
    }

    MouseArea {
        id: handleArea
        anchors.fill: parent
        anchors.topMargin: -10
        anchors.bottomMargin: -10
        enabled: !root.disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor

        drag.target: handle
        drag.axis: Drag.XAxis
        drag.minimumX: 0
        drag.maximumX: root.width - handle.width

        onPressed: function (mouse) {
            const newX = Math.max(0, Math.min(mouse.x - handle.width / 2, root.width - handle.width));
            handle.x = newX;
            updateValue();
        }
        onReleased: root.released()
        onPositionChanged: {
            if (drag.active)
                updateValue();
        }

        function updateValue() {
            const ratio = handle.x / (root.width - handle.width);
            root.value = root.from + ratio * (root.to - root.from);
            root.moved();
        }
    }
}
