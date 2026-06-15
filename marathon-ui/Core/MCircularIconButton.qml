import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

Item {
    id: root

    property string iconName: ""
    property string text: ""
    property int iconSize: 28
    property color iconColor: variant === "primary" ? "#000000" : MColors.textOnAccent
    property color textColor: MColors.textPrimary
    property bool disabled: false
    property string variant: "primary"
    property int buttonSize: 62
    // Default a11y label uses the visible text or, failing that, the icon name.
    property string a11yName: text.length > 0 ? text : iconName
    readonly property real scaleFactor: Constants.scaleFactor || 1
    readonly property real scaledButtonSize: Math.round(buttonSize * scaleFactor)
    readonly property real scaledIconSize: Math.round(iconSize * scaleFactor)
    readonly property real scaledBorderSize: Math.round(3 * scaleFactor)
    readonly property bool hasText: text !== ""
    readonly property real haloPadding: scaledBorderSize + Math.round(3 * scaleFactor)
    readonly property real renderDiameter: Math.min(width, height)
    readonly property real innerDiameter: Math.max(0, renderDiameter - haloPadding * 2)
    readonly property real effectiveIconSize: Math.min(scaledIconSize, Math.floor(innerDiameter * 0.5))

    signal clicked

    Accessible.role: Accessible.Button
    Accessible.name: a11yName
    Accessible.onPressAction: {
        if (!disabled) {
            clicked();
        }
    }
    implicitWidth: scaledButtonSize + haloPadding * 2
    implicitHeight: implicitWidth

    Rectangle {
        anchors.centerIn: parent
        width: root.renderDiameter
        height: root.renderDiameter
        radius: width / 2
        color: "transparent"
        border.width: scaledBorderSize
        border.color: variant === "primary" ? Qt.rgba(0, 191 / 255, 165 / 255, 0.35) : Qt.rgba(1, 1, 1, 0.08)
        opacity: variant === "primary" ? 1 : 0.6
    }

    Rectangle {
        id: mainButton

        anchors.centerIn: parent
        width: root.innerDiameter
        height: root.innerDiameter
        radius: width / 2
        color: {
            if (disabled)
                return MColors.surface;

            if (variant === "primary")
                return mouseArea.pressed ? MColors.marathonTealDark : "transparent";

            return mouseArea.pressed ? MColors.elevated : MColors.surface;
        }
        gradient: variant === "primary" && !disabled && !mouseArea.pressed ? primaryGradient : null
        border.width: variant === "secondary" ? Math.max(1, Math.round(1 * scaleFactor)) : 0
        border.color: MColors.borderGlass
        scale: mouseArea.pressed ? 0.96 : 1

        Gradient {
            id: primaryGradient

            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: MColors.marathonTealBright
            }

            GradientStop {
                position: 0.5
                color: MColors.marathonTeal
            }

            GradientStop {
                position: 1
                color: MColors.marathonTealDark
            }
        }

        Rectangle {
            visible: variant === "primary"
            anchors.fill: parent
            anchors.margins: Math.max(1, Math.round(1 * scaleFactor))
            radius: parent.radius - Math.max(1, Math.round(1 * scaleFactor))
            color: "transparent"
            border.width: Math.max(1, Math.round(1 * scaleFactor))
            border.color: Qt.rgba(1, 1, 1, 0.1)
        }

        Rectangle {
            visible: variant === "primary"
            anchors.fill: parent
            anchors.margins: Math.max(2, Math.round(2 * scaleFactor))
            radius: parent.radius - Math.max(2, Math.round(2 * scaleFactor))
            opacity: 0.6

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, 0.3)
                }

                GradientStop {
                    position: 0.5
                    color: "transparent"
                }
            }
        }

        Icon {
            visible: !hasText
            name: root.iconName
            size: root.effectiveIconSize
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
            font.pixelSize: root.effectiveIconSize
            font.weight: Font.Light
            font.family: MTypography.fontFamily
            anchors.centerIn: parent

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.xs
                }
            }
        }

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
    }

    // Hit area covers the full root Item, not just the inner button —
    // expanding the touch target by the outer ring + 6 px padding.
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: !disabled
        onPressed: MHaptics.lightImpact()
        onClicked: {
            if (!disabled) {
                root.clicked();
            }
        }
    }
}
