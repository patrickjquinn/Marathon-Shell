import QtQuick
import QtQuick.Effects
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
// Surface treatment (matches Marathon button reference shots):
//   • Primary
//       - Vertical teal-gradient (teal-bright top → teal-dark bottom)
//       - 1 px teal-border outer ring
//       - 1 px white-30 inset highlight along the TOP edge ONLY
//         (not a full 4-sided inner stroke — the look is "lit from above")
//       - Soft outer teal-halo bloom around the whole button via
//         MultiEffect drop shadow.
//   • Secondary — bb10-surface fill, w-08 outer, top-only w-04 highlight.
//   • Ghost     — transparent, w-08 outer ring, no highlight, no halo.
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

        border.width: 1
        border.color: {
            if (root.isPrimary)
                return MColors.tealBorder;
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
        // rgba(255,255,255,0.25); .secondary uses w-04). 1 px tall, sits
        // just inside the top border to give the "lit from above" look —
        // not a full 4-sided inner stroke.
        Rectangle {
            visible: !root.disabled && root.variant !== "ghost"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            anchors.topMargin: 1
            height: 1
            color: root.isPrimary ? Qt.rgba(1, 1, 1, 0.30) : MColors.whiteOverlay04
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

        // MultiEffect-rendered teal halo only on primary buttons. Real
        // box-shadow at 8px blur, 0px offset, teal-halo colour — gives
        // the "lit from within" outer bloom from the JSX reference.
        layer.enabled: root.isPrimary && !root.disabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            shadowColor: Qt.rgba(0, 191 / 255, 165 / 255, 0.55)
            shadowOpacity: 0.9
            shadowScale: 1.05
        }

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
