import QtQuick
import QtQuick.Effects
import MarathonUI.Theme
import MarathonUI.Effects
import MarathonOS.Shell

Item {
    id: root

    property bool checked: false
    property bool disabled: false

    signal toggled

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
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

    implicitWidth: Math.max(toggleWidth, parent ? Math.min(parent.width, toggleWidth) : toggleWidth)
    implicitHeight: toggleHeight

    Accessible.role: Accessible.CheckBox
    Accessible.name: "Toggle switch"
    Accessible.checked: checked
    Accessible.onToggleAction: if (!disabled)
        toggle()
    Accessible.onPressAction: if (!disabled)
        toggle()

    focus: true
    Keys.onReturnPressed: if (!disabled)
        toggle()
    Keys.onSpacePressed: if (!disabled)
        toggle()

    function toggle() {
        if (!disabled) {
            checked = !checked;
            toggled();
            MHaptics.lightImpact();
        }
    }

    // Track background with proper MUIstyling
    Rectangle {
        id: track
        anchors.fill: parent
        radius: MRadius.md
        color: root.checked ? MColors.marathonTeal : MColors.bb10Surface
        border.width: borderWidth
        border.color: root.checked ? MColors.marathonTealBright : MColors.borderGlass

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

        layer.enabled: false

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
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.15)
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
            opacity: 0.6
        }
    }

    // Thumb (handle) with proper MUIstyling
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

        Behavior on x {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        Rectangle {
            id: thumb
            anchors.centerIn: parent
            width: thumbInnerWidth
            height: thumbInnerHeight
            radius: MRadius.md > innerMargin ? MRadius.md - innerMargin : 0

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, 1.0)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0.92, 0.92, 0.92, 1.0)
                }
            }

            // Outer border
            border.width: borderWidth
            border.color: Qt.rgba(0, 0, 0, 0.15)

            // Shadow on thumb
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.4)
                shadowVerticalOffset: 2
                shadowBlur: 0.4
                blurMax: 6
            }

            // Inner highlight for polish
            Rectangle {
                anchors.fill: parent
                anchors.margins: innerMargin
                radius: parent.radius > innerMargin ? parent.radius - innerMargin : 0
                color: "transparent"
                border.width: borderWidth
                border.color: Qt.rgba(1, 1, 1, 0.4)
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
