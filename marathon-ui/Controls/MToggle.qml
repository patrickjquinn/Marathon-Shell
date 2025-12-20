import MarathonOS.Shell
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

Item {
    // Thumb (handle) with proper MUIstyling

    id: root

    property bool checked: false
    property bool disabled: false
    readonly property real scaleFactor: Constants.scaleFactor || 1
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real borderWidthThick: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real thumbWidth: Math.round(26 * scaleFactor)
    readonly property real thumbHeight: Math.round(26 * scaleFactor)
    readonly property real thumbInnerWidth: Math.round(22 * scaleFactor)
    readonly property real thumbInnerHeight: Math.round(22 * scaleFactor)
    readonly property real thumbOffset: Math.max(1, Math.round(3 * scaleFactor))
    readonly property real innerMargin: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real shadowMargin: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real toggleWidth: Math.round(76 * scaleFactor)
    readonly property real toggleHeight: Math.round(32 * scaleFactor)

    signal toggled

    function toggle() {
        if (!disabled) {
            checked = !checked;
            toggled();
            MHaptics.lightImpact();
        }
    }

    implicitWidth: Math.max(toggleWidth, parent ? Math.min(parent.width, toggleWidth) : toggleWidth)
    implicitHeight: toggleHeight
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

    // Track background with proper MUIstyling
    Rectangle {
        id: track

        anchors.fill: parent
        radius: MRadius.md
        color: root.checked ? MColors.marathonTeal : MColors.bb10Surface
        border.width: borderWidth
        border.color: root.checked ? MColors.marathonTealBright : MColors.borderGlass
        layer.enabled: false

        // Performant subtle shadow (no GPU blur needed)
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: shadowMargin
            anchors.leftMargin: -innerMargin
            anchors.rightMargin: -innerMargin
            anchors.bottomMargin: -shadowMargin
            z: -1
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0.3
        }

        // Inner border for dual-border depth
        Rectangle {
            anchors.fill: parent
            anchors.margins: innerMargin
            radius: parent.radius > innerMargin ? parent.radius - innerMargin : 0
            color: "transparent"
            border.width: borderWidth
            border.color: root.checked ? Qt.rgba(0, 191 / 255, 165 / 255, 0.3) : MColors.borderSubtle

            Behavior on border.color {
                ColorAnimation {
                    duration: MMotion.md
                }
            }
        }

        // Subtle inner glow when checked
        Rectangle {
            visible: root.checked
            anchors.fill: parent
            anchors.margins: shadowMargin
            radius: parent.radius > shadowMargin ? parent.radius - shadowMargin : 0
            opacity: 0.6

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.15)
                }

                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: MMotion.quick
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: MMotion.md
            }
        }
    }

    // IMPORTANT:
    // Avoid `layer.effect` (MultiEffect) here. On some platforms/backends it can fail and
    // the thumb disappears entirely, leaving only the track (what you reported).
    Rectangle {
        id: thumbOuter

        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - thumbOffset : thumbOffset
        width: thumbWidth
        height: thumbHeight
        radius: MRadius.md
        color: "transparent"
        // Teal border ring for consistency
        border.width: borderWidthThick
        border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)

        // Simple shadow under the thumb (no shader/effect dependency)
        Rectangle {
            anchors.centerIn: parent
            width: thumbInnerWidth
            height: thumbInnerHeight
            radius: MRadius.md > innerMargin ? MRadius.md - innerMargin : 0
            color: Qt.rgba(0, 0, 0, 0.35)
            opacity: 0.25
            anchors.verticalCenterOffset: 2 * scaleFactor
            z: -1
        }

        Rectangle {
            id: thumb

            anchors.centerIn: parent
            width: thumbInnerWidth
            height: thumbInnerHeight
            radius: MRadius.md > innerMargin ? MRadius.md - innerMargin : 0
            // Outer border
            border.width: borderWidth
            border.color: Qt.rgba(0, 0, 0, 0.15)

            // Inner highlight for polish
            Rectangle {
                anchors.fill: parent
                anchors.margins: innerMargin
                radius: parent.radius > innerMargin ? parent.radius - innerMargin : 0
                color: "transparent"
                border.width: borderWidth
                border.color: Qt.rgba(1, 1, 1, 0.4)
            }

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, 1)
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(0.92, 0.92, 0.92, 1)
                }
            }
        }

        Behavior on x {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
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
