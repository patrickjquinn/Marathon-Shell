import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

// Marathon DS · Quick Settings slider.
//
// Per docs/redesign/marathonos/project/design-system/ds-components.jsx::DSInputs
// the SYSTEM slider is a pill-shaped container with the icon on the
// left, a 4 px teal-gradient track, and a 16 px white thumb that
// carries a soft teal-halo glow (NOT a hard teal border).
//
// Container:  --elev-2 background, 1 px --w-04 border, full pill radius
// Padding:    14 px vertical, 16 px horizontal
// Icon:       20 px, --text-primary
// Track:      4 px, --w-08, radius 2, pill end-caps
// Fill:       --teal-gradient (dark → bright), same radius as track
// Thumb:      16 px white disc, halo via shadow `0 0 8px var(--teal-halo)`
//             + soft drop shadow `0 2px 4px rgba(0,0,0,0.4)`
//
// Quick Settings stacks BRIGHTNESS over VOLUME with an internal
// hairline divider, both inside ONE pill container per the screenshot.
// This component renders a SINGLE row — the QS panel composes two
// in a column inside one shared MCard.
Item {
    id: root

    property string iconName: "brightness"
    property string label: ""
    property real value: 50          // 0..100
    property real from: 0
    property real to: 100

    signal moved(real value)           // user dragged — caller commits

    // Match the spec block: icon (20) on left, label/value row + track.
    // Height 36 fits comfortably inside a 60 px-tall slider card.
    implicitHeight: 36

    readonly property real fraction: (value - from) / Math.max(1, to - from)

    Row {
        anchors.fill: parent
        spacing: 12

        // Icon — 20 px primary-text colour per DS Inputs slider.
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: 20
            color: MColors.textPrimary
        }

        // Label / value + track.
        Item {
            id: stack
            width: parent.width - 20 - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            // LABEL — TINY UPPERCASE TRACKED — DS eyebrow style. value on the right.
            Item {
                id: labels
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                height: labelText.implicitHeight

                Text {
                    id: labelText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.label
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightDemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: MTypography.trackingEyebrow
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(root.value)
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightDemiBold
                    font.features: ({
                            "tnum": 1
                        })
                }
            }

            // TRACK — 4 px, --w-08, pill end-caps.
            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                height: 4
                radius: 2
                color: MColors.whiteOverlay08

                // FILL — teal gradient.
                Rectangle {
                    width: Math.max(parent.height, parent.width * root.fraction)
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealDark
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTealBright
                        }
                    }
                }

                // THUMB — 16 px white disc with soft drop shadow.
                //
                // The DS spec calls for `0 2px 4px rgba(0,0,0,0.4),
                // 0 0 8px var(--teal-halo)`. Qt's MultiEffect supports
                // ONE shadow per layer, so we paint the dark drop here
                // and the teal halo as a small inset Rectangle BEHIND
                // the thumb whose footprint is constrained to the
                // thumb's bounding box so it can never overflow the
                // slider's parent card (a previous attempt with a
                // 30×30 halo Rectangle was the root cause of the QS
                // sliders pushing past their container).
                Rectangle {
                    id: thumbHalo
                    width: 20
                    height: 20
                    radius: 10
                    // Soft teal halo behind the thumb. Sized so it
                    // never exceeds the thumb width + 4 — fits inside
                    // the 4 px track height plus the thumb's own
                    // overhang without bleeding into the row below.
                    color: Qt.rgba(29 / 255, 233 / 255, 182 / 255, 0.28)
                    x: thumb.x + thumb.width / 2 - width / 2
                    y: thumb.y + thumb.height / 2 - height / 2
                    z: 0
                }

                Rectangle {
                    id: thumb
                    width: 16
                    height: 16
                    radius: 8
                    color: "#ffffff"
                    x: Math.max(0, Math.min(track.width - width, track.width * root.fraction - width / 2))
                    y: (track.height - height) / 2
                    z: 1

                    // Soft dark drop shadow per DS spec, no scale-up
                    // so the effect stays within the thumb's own bbox.
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowBlur: 0.8
                        shadowVerticalOffset: 2
                        shadowHorizontalOffset: 0
                        shadowColor: Qt.rgba(0, 0, 0, 0.4)
                        shadowOpacity: 1.0
                    }
                }
            }

            MouseArea {
                anchors.fill: track
                anchors.topMargin: -12
                anchors.bottomMargin: -12
                onPressed: drag(mouseX)
                onPositionChanged: {
                    if (pressed)
                        drag(mouseX);
                }
                function drag(x) {
                    const f = Math.max(0, Math.min(1, x / track.width));
                    root.value = root.from + f * (root.to - root.from);
                    root.moved(root.value);
                }
            }
        }
    }
}
