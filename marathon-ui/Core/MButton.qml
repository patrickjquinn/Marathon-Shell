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
// Surface treatment per the marathon-tokens.css spec. Spec text:
//
//   .m-btn.primary {
//     background: linear-gradient(180deg, #1de9b6 0%, #00bfa5 50%, #00897b 100%);
//     color: #000;
//     border: 1 px solid rgba(0,191,165,0.35);
//     box-shadow:
//       inset 0 1px 0 rgba(255,255,255,0.25),     /* top inset highlight */
//       0 0 0 1px rgba(0,191,165,0.35),           /* outer ring (extra) */
//       0 8px 24px -8px rgba(0,191,165,0.5);      /* cast-down glow    */
//   }
//
// The "complex border" is the two stacked 1 px teal rings (the
// element's own border + the outer `0 0 0 1px` box-shadow) plus a
// 1 px white top highlight inside. Reads as a thick, depth-having
// edge — that's what the reference shows.
//
// Cast-down glow uses the exact spec values: blur 24, spread -8,
// y-offset 8, teal at 50% alpha. Source ends 8 px inside the button
// on every side and shifts 8 px down → visible extent is small
// above (~8 px), larger below (~24 px), modest on sides (~16 px).
// Smaller than the previous over-shot MultiEffect and bounded
// enough to coexist with a 14 px modal padding without bleeding
// outside the dialog when the consumer keeps the spec padding.
//
// Other variants:
//   • Secondary — bb10-surface fill, w-08 outer, top-only w-04 highlight.
//   • Ghost     — transparent, w-08 outer ring, no highlight, no glow.
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

    // Cast-down glow is opt-in. Qt's MultiEffect renders the halo to an
    // FBO whose composite geometry ignores ancestor clip, so the 24 px DS
    // reach leaks past rounded parents (modals, narrow list rows). Primary
    // identity is carried by the teal gradient + double-ring edge + top
    // hairline; the halo is decoration for large hero CTAs only.
    property bool castGlow: false

    // Optional text-color override. When unset (the default), the variant
    // chooses the colour (black on primary gradient, error-red on danger,
    // textPrimary elsewhere). Used by callers like the lock screen's
    // Emergency button — semantically `ghost` (clickable text, no shell)
    // but still wants the red E911 signifier from MColors.error.
    property color textColor: "transparent"

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
    readonly property real horizontalPadding: Math.round((size === "large" ? 22 : 18) * scaleFactor)
    // Hand off to MTypography so the text scales with the DS canvas the
    // same way the button height does. Hard-coded 13/14/15 px was the
    // smoking gun behind "buttons look weirdly tall with small text" —
    // the box scaled with DPI, the glyphs didn't.
    readonly property real fontSize: size === "compact" ? MTypography.sizeFootnote : (size === "large" ? MTypography.sizeBody : MTypography.sizeSubhead)
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

    // ── Primary cast-down glow ─────────────────────────────────
    // CSS: `0 8px 24px -8px rgba(0,191,165,0.5)`
    // Source rect = button shrunk by 8 each side, offset down 8.
    // Blur radius 24 → visible reach: ~8 px above, ~24 px below,
    // ~16 px past each side. The shadow pools BELOW the button per
    // the spec's directional cast-down characteristic.
    Item {
        id: shadowContainer
        anchors.fill: buttonRect
        anchors.margins: -24
        z: -1
        visible: root.isPrimary && !root.disabled && root.castGlow

        Rectangle {
            id: shadowSource
            x: 24 + 8                         // 24 container inset + 8 spread inset
            y: 24 + 8 + 8                     // 24 + 8 spread + 8 y-offset
            width: buttonRect.width - 16      // -8 spread each side
            height: buttonRect.height - 16
            radius: MRadius.md
            color: Qt.rgba(0, 191 / 255, 165 / 255, 0.5)
            visible: false
            layer.enabled: shadowContainer.visible
            layer.smooth: true
        }

        MultiEffect {
            anchors.fill: parent
            source: shadowSource
            blurEnabled: true
            blur: 1.0
            blurMax: 24
        }
    }

    // ── Outer extra ring ───────────────────────────────────────
    // CSS box-shadow layer 2: `0 0 0 1px var(--teal-border)`.
    // A 1 px ring sitting 1 px OUTSIDE the buttonRect.border, with
    // no offset and no blur. Stacks with the button's own border to
    // give the primary variant its signature double-ring edge.
    Rectangle {
        anchors.fill: buttonRect
        anchors.margins: -1
        radius: MRadius.md + 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
        visible: root.isPrimary && !root.disabled
        z: -1
    }

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

        // Three-stop teal gradient per CSS spec:
        //   linear-gradient(180deg, #1de9b6 0%, #00bfa5 50%, #00897b 100%)
        // The 50%-stop mid-tone is what gives the body its visible
        // top-to-mid brightness band before fading to the deeper
        // teal at the bottom. A 2-stop gradient lacks that bend.
        gradient: root.isPrimary ? primaryGradient : null
        Gradient {
            id: primaryGradient
            orientation: Gradient.Vertical
            GradientStop {
                position: 0.0
                color: "#1de9b6"
            }
            GradientStop {
                position: 0.5
                color: "#00bfa5"
            }
            GradientStop {
                position: 1.0
                color: "#00897b"
            }
        }

        // Inner ring — 1 px teal-border. Pairs with the outer extra
        // teal ring (a sibling drawn at -1 px margins) to form the
        // signature stacked double-ring edge from the DS spec.
        border.width: 1
        border.color: {
            if (root.isPrimary)
                return Qt.rgba(0, 191 / 255, 165 / 255, 0.35);
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

        // CSS box-shadow layer 1: `inset 0 1px 0 rgba(255,255,255,0.25)`.
        // A 1 px white-25 highlight along the top inside edge,
        // tracing the corner radius so the curve at the corners
        // stays clean.
        MTopHairline {
            visible: !root.disabled && root.variant !== "ghost"
            radius: MRadius.md
            color: root.isPrimary ? Qt.rgba(1, 1, 1, 0.25) : MColors.whiteOverlay04
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
                    // Caller override wins when set (alpha=0 sentinel
                    // means "use variant default").
                    if (root.textColor.a > 0)
                        return root.textColor;
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
