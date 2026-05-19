import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

// Marathon DS · Button (ds-components.jsx:DSButtons · marathon-tokens.css .m-btn).
//
// Heights: 45 default · 38 compact · 50 large CTA.
// Radius 4 px (--r-md). Padding 0 18 px (22+ for large). Font 14/600 Sora.
// Press: scale(0.96), 160 ms spring (--ease-spring).
//
// Surface treatment per the Marathon button reference (Continue >):
//   • Primary
//       - Vertical teal gradient (teal-bright top → teal-dark bottom).
//       - 1 px black/dark-teal outer ring.
//       - 1 px white-30 top-edge inner highlight following the corner
//         radius (MTopHairline).
//       - NO outer glow/halo. The button is self-contained; the visual
//         interest is the gradient + ring + top highlight. Earlier
//         iterations rendered a MultiEffect bloom that read as either
//         a hard-edged rectangle around the button or a teal smear
//         leaking past containing modals — both wrong per the
//         reference image, which shows zero external glow.
//   • Secondary — bb10-surface fill, w-08 outer, top-only w-04 highlight.
//   • Ghost     — transparent, w-08 outer ring, no highlight.
//   • Danger    — bb10-surface fill, error-30 outer, error text.
Item {
    id: root

    required property string text
    property string variant: "secondary"
    property string size: "default"           // "default" | "compact" | "large"
    property string iconName: ""
    property bool iconLeft: true
    property bool disabled: false
    property string state: "default"          // "default" | "loading" | "success"

    signal clicked
    signal pressed
    signal released

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real buttonHeight: {
        if (size === "compact")
            return Math.round(38 * scaleFactor);
        if (size === "large")
            return Math.round(50 * scaleFactor);
        return Math.round(45 * scaleFactor);
    }
    readonly property real horizontalPadding: size === "large" ? 22 : 18
    readonly property real fontSize: size === "compact" ? 13 : (size === "large" ? 15 : 14)
    readonly property real iconSize: Math.round((size === "large" ? 20 : 18) * scaleFactor)
    readonly property bool isPrimary: variant === "primary"

    implicitHeight: buttonHeight
    implicitWidth: contentRow.width + horizontalPadding * 2

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
        id: buttonRect
        anchors.fill: parent
        radius: MRadius.md

        color: {
            if (root.disabled)
                return Qt.rgba(1, 1, 1, 0.02);
            if (root.isPrimary)
                return mouseArea.pressed ? MColors.marathonTealDark : "transparent";
            if (root.variant === "secondary")
                return mouseArea.pressed ? MColors.bb10Elevated : MColors.bb10Surface;
            if (root.variant === "danger")
                return mouseArea.pressed ? MColors.bb10Elevated : MColors.bb10Surface;
            // ghost
            return mouseArea.pressed ? Qt.rgba(1, 1, 1, 0.04) : "transparent";
        }

        gradient: root.isPrimary ? primaryGradient : null
        Gradient {
            id: primaryGradient
            orientation: Gradient.Vertical          // top-light → bottom-dark per JSX
            GradientStop {
                position: 0.0
                color: MColors.marathonTealBright
            }
            GradientStop {
                position: 1.0
                color: MColors.marathonTealDark
            }
        }

        // Outer ring. The primary reference shows a dark, near-black
        // edge against the teal fill — this is what separates the
        // button from the surrounding dark surface and gives the
        // top-edge highlight a clean wall to brighten against. The
        // previous teal-on-teal ring read as a soft edge.
        border.width: 1
        border.color: {
            if (root.isPrimary)
                return Qt.rgba(0, 0, 0, 0.6);
            if (root.variant === "danger")
                return Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.3);
            return MColors.whiteOverlay08;
        }

        scale: mouseArea.pressed ? 0.96 : 1.0
        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: MMotion.quick
            }
        }

        // Top-edge inset highlight per JSX m-btn (.primary uses
        // rgba(255,255,255,0.30); .secondary uses w-04). Traces the
        // top arc of buttonRect so it follows the corner radius
        // instead of stopping short at a flat line past the curve.
        MTopHairline {
            visible: !root.disabled && root.variant !== "ghost"
            radius: MRadius.md
            color: root.isPrimary ? Qt.rgba(1, 1, 1, 0.30) : MColors.whiteOverlay04
            inset: 2
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 8
            layoutDirection: root.iconLeft ? Qt.LeftToRight : Qt.RightToLeft
            opacity: root.state === "loading" ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.quick
                }
            }

            Icon {
                visible: root.iconName !== "" && root.state === "default"
                anchors.verticalCenter: parent.verticalCenter
                name: root.iconName
                size: root.iconSize
                color: root.isPrimary ? "#000000" : MColors.textPrimary
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                color: {
                    if (root.disabled)
                        return MColors.textHint;
                    if (root.isPrimary)
                        return "#000000";
                    if (root.variant === "danger")
                        return MColors.error;
                    return MColors.textPrimary;
                }
                font.family: MTypography.fontFamily
                font.pixelSize: root.fontSize
                font.weight: Font.DemiBold          // 600 per DS
            }
        }

        // Success indicator
        Icon {
            anchors.centerIn: parent
            name: "check"
            size: root.iconSize
            color: root.isPrimary ? "#000000" : MColors.success
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

        // (Halo lives on the sibling haloSource + MultiEffect above.)

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: !root.disabled && root.state === "default"

            onPressed: {
                MHaptics.lightImpact();
                root.pressed();
            }
            onReleased: root.released()
            onClicked: root.clicked()
        }
    }
}
