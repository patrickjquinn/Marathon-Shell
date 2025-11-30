import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

Item {
    id: root

    required property string text
    property string variant: "default"
    property string iconName: ""
    property bool iconLeft: true
    property bool disabled: false
    property string state: "default"
    property string shape: "rounded"  // "rounded" or "circular"

    signal clicked
    signal pressed
    signal released

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real borderGlowWidth: Math.max(1, Math.round(3 * scaleFactor))
    readonly property real borderGlowOffset: Math.max(1, Math.round(3 * scaleFactor))
    readonly property real iconSize: Math.round(18 * scaleFactor)

    implicitWidth: buttonRect.implicitWidth + borderGlowOffset * 2
    implicitHeight: buttonRect.implicitHeight + borderGlowOffset * 2

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.description: variant + " button"
    Accessible.onPressAction: if (!disabled && state === "default")
        clicked()

    focus: true
    Keys.onReturnPressed: if (!disabled && state === "default")
        clicked()
    Keys.onSpacePressed: if (!disabled && state === "default")
        clicked()

    Rectangle {
        visible: variant === "primary"
        anchors.centerIn: parent
        width: buttonRect.width + borderGlowOffset * 2
        height: buttonRect.height + borderGlowOffset * 2
        radius: buttonRect.radius + borderGlowOffset
        color: "transparent"
        border.width: borderGlowWidth
        border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
    }

    Rectangle {
        id: buttonRect
        anchors.centerIn: parent

        implicitWidth: contentRow.width + MSpacing.xl * 2
        implicitHeight: MSpacing.touchTargetMin

        // Always subtract glow offset to ensure containment and stability
        // This prevents jumping when switching variants and clipping in tight layouts
        width: (root.width > 0 ? root.width : root.implicitWidth) - borderGlowOffset * 2
        height: (root.height > 0 ? root.height : root.implicitHeight) - borderGlowOffset * 2

        radius: root.shape === "circular" ? width / 2 : MRadius.md
        color: {
            if (root.disabled)
                return Qt.rgba(1, 1, 1, 0.02);
            if (mouseArea.pressed) {
                if (root.variant === "primary")
                    return MColors.marathonTealDark;
                if (root.variant === "secondary")
                    return MColors.bb10Elevated;
                return "transparent";
            }
            if (root.variant === "primary")
                return MColors.marathonTeal;
            if (root.variant === "secondary")
                return MColors.bb10Surface;
            return "transparent";
        }

        border.width: root.variant === "default" ? borderWidth : 0
        border.color: MColors.borderGlass

        scale: mouseArea.pressed ? 0.96 : 1.0

        gradient: root.variant === "primary" ? primaryGradient : null

        Gradient {
            id: primaryGradient
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: MColors.marathonTealBright
            }
            GradientStop {
                position: 0.5
                color: MColors.marathonTeal
            }
            GradientStop {
                position: 1.0
                color: MColors.marathonTealDark
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: MMotion.xs
            }
        }

        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: MSpacing.sm
            layoutDirection: iconLeft ? Qt.LeftToRight : Qt.RightToLeft
            opacity: root.state === "loading" ? 0 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.quick
                }
            }

            Icon {
                visible: iconName !== "" && root.state === "default"
                name: iconName
                size: iconSize
                color: variant === "primary" ? "#000000" : MColors.textPrimary  // Black icon on teal
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.text
                color: {
                    if (disabled)
                        return MColors.textHint;
                    if (variant === "primary")
                        return "#000000";  // Pure black for maximum contrast on teal
                    if (variant === "secondary")
                        return MColors.textPrimary;
                    return MColors.textPrimary;
                }
                font.pixelSize: MTypography.sizeBody  // Larger for readability
                font.weight: variant === "primary" ? MTypography.weightBold : MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Icon {
            anchors.centerIn: parent
            name: "check"
            size: iconSize
            color: root.variant === "primary" ? MColors.textOnAccent : MColors.success
            visible: root.state === "success"
            scale: root.state === "success" ? 1 : 0

            Behavior on scale {
                SpringAnimation {
                    spring: MMotion.springLight
                    damping: MMotion.dampingLight
                    epsilon: MMotion.epsilon
                }
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: !root.disabled && root.state === "default"

            onPressed: function (mouse) {
                MHaptics.lightImpact();
                root.pressed();
            }
            onReleased: root.released()
            onClicked: root.clicked()
        }
    }
}
