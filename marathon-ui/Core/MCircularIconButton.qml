import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

Item {
    id: root

    property string iconName: ""
    property string text: ""
    property int iconSize: 28
    property color iconColor: variant === "primary" ? "#000000" : MColors.textOnAccent
    property color textColor: MColors.textPrimary
    property bool disabled: false
    property string variant: "primary"  // "primary" or "secondary"
    property int buttonSize: 62

    signal clicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real scaledButtonSize: Math.round(buttonSize * scaleFactor)
    readonly property real scaledIconSize: Math.round(iconSize * scaleFactor)
    readonly property real scaledBorderSize: Math.round(3 * scaleFactor)
    readonly property bool hasText: text !== ""

    implicitWidth: scaledButtonSize + (scaledBorderSize * 2) + Math.round(6 * scaleFactor)
    implicitHeight: scaledButtonSize + (scaledBorderSize * 2) + Math.round(6 * scaleFactor)

    // Outer glow border (like action bar)
    Rectangle {
        anchors.centerIn: parent
        width: scaledButtonSize + (scaledBorderSize * 2) + Math.round(6 * scaleFactor)
        height: scaledButtonSize + (scaledBorderSize * 2) + Math.round(6 * scaleFactor)
        radius: width / 2
        color: "transparent"
        border.width: scaledBorderSize
        border.color: variant === "primary" ? Qt.rgba(0, 191 / 255, 165 / 255, 0.35) : Qt.rgba(1, 1, 1, 0.08)
        opacity: variant === "primary" ? 1.0 : 0.6
    }

    // Main button
    Rectangle {
        id: mainButton
        anchors.centerIn: parent
        width: scaledButtonSize
        height: scaledButtonSize
        radius: width / 2

        color: {
            if (disabled)
                return MColors.surface;
            if (variant === "primary") {
                return mouseArea.pressed ? MColors.marathonTealDark : "transparent";
            }
            return mouseArea.pressed ? MColors.elevated : MColors.surface;
        }

        gradient: variant === "primary" && !disabled && !mouseArea.pressed ? primaryGradient : null

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

        border.width: variant === "secondary" ? Math.max(1, Math.round(1 * scaleFactor)) : 0
        border.color: MColors.borderGlass

        scale: mouseArea.pressed ? 0.96 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: MMotion.xs
            }
        }

        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springLight
                damping: MMotion.dampingLight
                epsilon: MMotion.epsilon
            }
        }

        // Inner highlight border (for primary)
        Rectangle {
            visible: variant === "primary"
            anchors.fill: parent
            anchors.margins: Math.max(1, Math.round(1 * scaleFactor))
            radius: parent.radius - Math.max(1, Math.round(1 * scaleFactor))
            color: "transparent"
            border.width: Math.max(1, Math.round(1 * scaleFactor))
            border.color: Qt.rgba(1, 1, 1, 0.1)
        }

        // Top highlight gradient (for primary)
        Rectangle {
            visible: variant === "primary"
            anchors.fill: parent
            anchors.margins: Math.max(2, Math.round(2 * scaleFactor))
            radius: parent.radius - Math.max(2, Math.round(2 * scaleFactor))
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, 0.3)
                }
                GradientStop {
                    position: 0.5
                    color: "transparent"
                }
            }
            opacity: 0.6
        }

        Icon {
            visible: !hasText
            name: root.iconName
            size: scaledIconSize
            color: {
                if (disabled)
                    return MColors.textHint;
                if (variant === "primary")
                    return iconColor;
                return MColors.textPrimary;
            }
            anchors.centerIn: parent

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.xs
                }
            }
        }

        Text {
            visible: hasText
            text: root.text
            color: {
                if (disabled)
                    return MColors.textHint;
                if (variant === "primary")
                    return iconColor;
                return textColor;
            }
            font.pixelSize: scaledIconSize
            font.weight: Font.Light
            font.family: MTypography.fontFamily
            anchors.centerIn: parent

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.xs
                }
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: !disabled
            onPressed: MHaptics.lightImpact()
            onClicked: if (!disabled)
                root.clicked()
        }
    }
}
