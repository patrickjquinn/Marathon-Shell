import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

Item {
    id: root

    required property string iconName
    property int iconSize: 20
    property color iconColor: MColors.textPrimary
    property bool disabled: false
    property string variant: "ghost"
    property string shape: "square"
    // Optional accessible label override; defaults to the icon name. Callers
    // that show an icon-only button should set this to a verb ("Close", "Open
    // settings", "Decline call") so screen readers announce the action, not
    // the glyph.
    property string accessibleName: iconName

    signal clicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real borderGlowWidth: Math.max(1, Math.round(3 * scaleFactor))
    readonly property real borderGlowOffset: Math.max(1, Math.round(3 * scaleFactor))
    readonly property real scaledIconSize: Math.round(iconSize * scaleFactor)

    implicitWidth: MSpacing.touchTargetMedium
    implicitHeight: MSpacing.touchTargetMedium

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.ignored: disabled
    Accessible.onPressAction: if (!disabled)
        clicked()

    focus: true
    Keys.onReturnPressed: if (!disabled)
        clicked()
    Keys.onSpacePressed: if (!disabled)
        clicked()

    Rectangle {
        visible: variant === "primary"
        anchors.centerIn: parent
        width: buttonRect.width + borderGlowOffset * 2
        height: buttonRect.height + borderGlowOffset * 2
        radius: shape === "circular" ? (width / 2) : (MRadius.md + borderGlowOffset)
        color: "transparent"
        border.width: borderGlowWidth
        border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
    }

    Rectangle {
        id: buttonRect
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight

        radius: shape === "circular" ? width / 2 : MRadius.md
        color: {
            if (disabled)
                return "transparent";
            if (mouseArea.pressed) {
                if (variant === "primary")
                    return MColors.marathonTealDark;
                if (variant === "secondary")
                    return MColors.bb10Elevated;
                return MColors.hover;
            }
            if (variant === "primary")
                return MColors.marathonTeal;
            if (variant === "secondary")
                return MColors.bb10Surface;
            return "transparent";
        }

        border.width: variant === "secondary" ? borderWidth : 0
        border.color: MColors.borderGlass

        scale: mouseArea.pressed ? 0.92 : 1.0

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

        Icon {
            name: iconName
            size: scaledIconSize
            color: disabled ? MColors.textHint : (variant === "primary" ? "#000000" : iconColor)
            anchors.centerIn: parent
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: !disabled
            onPressed: MHaptics.lightImpact()
            onClicked: root.clicked()
        }
    }
}
