import MarathonOS.Shell
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

// Marathon DS · Toggle (ds-components.jsx:DSInputs · "Toggle").
//
// 44 × 26. Thumb 20 px. Slides 18 px on toggle. Per the "Adapt to
// ambient light" reference shot, the ON state shows:
//   - Solid teal-bright pill (no gradient — matches the reference)
//   - 1 px teal-border outer ring
//   - White thumb pushed right
//   - Soft teal-halo bloom around the WHOLE pill via MultiEffect
//     (the entire control glows, not just the thumb)
// OFF state: bb10-surface fill, w-08 border, white thumb on left,
// no glow.
Item {
    id: root

    property bool checked: false
    property bool disabled: false

    readonly property real scaleFactor: Constants.scaleFactor || 1
    readonly property real trackWidth: Math.round(44 * scaleFactor)
    readonly property real trackHeight: Math.round(26 * scaleFactor)
    readonly property real thumbSize: Math.round(20 * scaleFactor)
    readonly property real thumbInset: Math.round(3 * scaleFactor)

    signal toggled

    function toggle() {
        if (!disabled) {
            checked = !checked;
            toggled();
            // Haptic moved from here to the thumb's SpringAnimation.
            // onStopped below — fires when the thumb actually LANDS
            // in the new position, not when the press registers. iOS
            // / M3 Expressive feel: user perceives the action complete
            // at settle, not at touch.
        }
    }

    implicitWidth: trackWidth
    implicitHeight: trackHeight

    Accessible.role: Accessible.CheckBox
    Accessible.name: "Toggle switch"
    Accessible.checked: checked
    Accessible.onToggleAction: {
        if (!disabled)
            toggle();
    }
    Accessible.onPressAction: {
        if (!disabled)
            toggle();
    }
    focus: true
    Keys.onReturnPressed: {
        if (!disabled)
            toggle();
    }
    Keys.onSpacePressed: {
        if (!disabled)
            toggle();
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? MColors.marathonTealBright : MColors.bb10Surface
        border.width: 1
        border.color: root.checked ? MColors.tealBorder : MColors.whiteOverlay08

        Behavior on color {
            ColorAnimation {
                duration: MMotion.quick
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: MMotion.quick
            }
        }

        // Outer teal halo — only renders when on, drawn via MultiEffect
        // drop shadow on the track for a real soft glow (no hard ring).
        layer.enabled: root.checked
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            shadowColor: Qt.rgba(0, 191 / 255, 165 / 255, 0.55)
            shadowOpacity: 0.85
            shadowScale: 1.10
        }
    }

    // Top-edge inset highlight per JSX (toggles in Settings carry a
    // subtle "lit from above" stripe so the pill reads as raised, not
    // pasted on). Traces the pill's top arc so the highlight runs
    // along the curved cap rather than ending abruptly inside it.
    MTopHairline {
        radius: parent.height / 2
        color: root.checked ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.06)
        inset: 2
    }

    // Thumb — white 20 px disc.
    Rectangle {
        id: thumb
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - thumbInset : thumbInset
        width: thumbSize
        height: thumbSize
        radius: width / 2
        color: "#FFFFFF"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.18)

        Behavior on x {
            SpringAnimation {
                spring: MMotion.stiffnessSpatialFor("tap")
                damping: MMotion.dampingSpatialFor("tap")
                epsilon: MMotion.epsilon
                onStopped: MHaptics.light()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        onClicked: root.toggle()
    }
}
