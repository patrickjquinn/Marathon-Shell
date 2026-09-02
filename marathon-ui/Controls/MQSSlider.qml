import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects
import MarathonOS.Shell

// Marathon DS · Quick Settings slider — BB10-modern hybrid.
//
// No text label. Icon LEFT, fat pill track CENTER, value pill RIGHT.
// Icon IS the label (sun = brightness, speaker = volume) — text would
// be redundant chrome. Matches BB10 / iOS Control Center pattern where
// the slider is just a control, not a labeled form field.
//
//   Row height          44 px
//   Icon                22 px, textPrimary
//   Track               8 px, whiteOverlay08, fully rounded
//   Fill                teal gradient (dark → bright)
//   Thumb               26 px white disc, soft dark drop + teal halo
//   Value pill          right edge, 28 px wide, Body tnum
Item {
    id: root
    
    // The track and thumb are deliberately NOT scaled: they sit inside a
    // fixed-height card, and scaling them by ~2.5 at userScaleFactor 1.50
    // produced thumbs that swallowed the row. Only the value column scales,
    // because its label uses MTypography.sizeFootnote, which does — a
    // three-digit value overflowed the fixed 36 px column and the leading
    // digit was occluded by the thumb, so max volume read "00".
    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property string iconName: "brightness"
    property real value: 50          // 0..100
    property real from: 0
    property real to: 100

    signal moved(real value)

    implicitHeight: 44

    readonly property real fraction: (value - from) / Math.max(1, to - from)

    // Single source of truth for the value column. The track width below
    // subtracted a hardcoded 36 for it; widening the column without updating
    // that arithmetic pushed the value clean off the right edge of the card.
    readonly property real valueWidth: Math.round(44 * scaleFactor)
    readonly property real rowSpacing: 14
    readonly property real iconSize: 22

    Row {
        anchors.fill: parent
        spacing: root.rowSpacing

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: root.iconSize
            color: MColors.textPrimary
        }

        // Track sits in the middle, sized to fill remaining space minus
        // the value pill on the right.
        Item {
            id: trackHost
            width: parent.width - root.iconSize - root.rowSpacing
                   - root.valueWidth - root.rowSpacing
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: MColors.whiteOverlay08

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

                Rectangle {
                    id: thumbHalo
                    width: 34
                    height: 34
                    radius: 17
                    color: Qt.rgba(29 / 255, 233 / 255, 182 / 255, 0.22)
                    x: thumb.x + thumb.width / 2 - width / 2
                    y: thumb.y + thumb.height / 2 - height / 2
                    z: 0
                }

                Rectangle {
                    id: thumb
                    width: 26
                    height: 26
                    radius: 13
                    color: "#ffffff"
                    x: Math.max(0, Math.min(track.width - width, track.width * root.fraction - width / 2))
                    y: (track.height - height) / 2
                    z: 1

                    // Press-scale per iOS / M3 Expressive — the thumb
                    // grows slightly while held so the user feels the
                    // grab. Halo follows because its x/y is bound to
                    // thumb's center.
                    scale: trackHit.pressed ? 1.15 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: MMotion.stiffnessSpatialFor("tap")
                            damping: MMotion.dampingSpatialFor("tap")
                            epsilon: MMotion.epsilon
                        }
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowBlur: 0.8
                        shadowVerticalOffset: 2
                        shadowHorizontalOffset: 0
                        shadowColor: Qt.rgba(0, 0, 0, 0.5)
                        shadowOpacity: 1.0
                    }
                }

                MouseArea {
                    id: trackHit
                    anchors.fill: track
                    anchors.topMargin: -16
                    anchors.bottomMargin: -16
                    // The Quick Settings shade is a Flickable at larger
                    // display scales, and this hit area is padded 16px
                    // vertically. Without this a slightly diagonal drag
                    // hands the grab to the Flickable mid-gesture: the
                    // press is cancelled and brightness sticks at whatever
                    // partial value it had reached while the shade scrolls.
                    preventStealing: true
                    // Continuous haptic on every value-step. iOS pulses
                    // at every integer crossing on the Control Center
                    // slider — same idea: gives the dragged track a
                    // physical "click" cadence.
                    property int _lastHapticStep: -1
                    onPressed: {
                        _lastHapticStep = -1;
                        applyDragAt(mouseX);
                    }
                    onReleased: {
                        // Release haptic = settle confirmation.
                        MHaptics.light();
                    }
                    onPositionChanged: {
                        if (pressed)
                            applyDragAt(mouseX);
                    }
                    // Not drag(): that is MouseArea's own grouped property.
                    function applyDragAt(x) {
                        const f = Math.max(0, Math.min(1, x / track.width));
                        root.value = root.from + f * (root.to - root.from);
                        const step = Math.round(root.value / 5) * 5;   // every 5%
                        if (step !== _lastHapticStep) {
                            _lastHapticStep = step;
                            MHaptics.light();
                        }
                        root.moved(root.value);
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // 3 digits at the scaled font, not 2 at the unscaled one.
            width: root.valueWidth
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.value)
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            font.weight: MTypography.weightDemiBold
            font.features: ({
                    "tnum": 1
                })
        }
    }
}
