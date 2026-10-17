import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

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

    property string iconName: "brightness"
    property real value: 50          // 0..100
    property real from: 0
    property real to: 100
    property string a11yName: ""

    signal moved(real value)

    implicitHeight: Silica.Theme.itemSizeExtraSmall

    Accessible.role: Accessible.Slider
    Accessible.name: a11yName

    readonly property real fraction: (value - from) / Math.max(1, to - from)

    // Single source of truth for the value column. The track width below
    // subtracted a hardcoded 36 for it; widening the column without updating
    // that arithmetic pushed the value clean off the right edge of the card.
    readonly property real valueWidth: Math.round(Silica.Theme.fontSizeSmall * 2)
    readonly property real rowSpacing: Silica.Theme.paddingLarge
    readonly property real iconSize: Silica.Theme.iconSizeSmall

    Row {
        anchors.fill: parent
        spacing: root.rowSpacing

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: root.iconSize
            color: Silica.Theme.primaryColor
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
                objectName: "sliderTrack"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.round(Silica.Theme.paddingSmall)
                radius: height / 2
                color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.15)

                Rectangle {
                    width: Math.max(parent.height, parent.width * root.fraction)
                    height: parent.height
                    radius: parent.radius
                    color: Silica.Theme.highlightColor
                }

                Rectangle {
                    id: thumbHalo
                    width: Silica.Theme.itemSizeExtraSmall / 2
                    height: width
                    radius: width / 2
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.3)
                    x: thumb.x + thumb.width / 2 - width / 2
                    y: thumb.y + thumb.height / 2 - height / 2
                    z: 0
                }

                Rectangle {
                    id: thumb
                    width: Math.round(Silica.Theme.iconSizeSmall * 0.7)
                    height: width
                    radius: width / 2
                    color: Silica.Theme.highlightColor
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
                }

                MouseArea {
                    id: trackHit
                    anchors.fill: track
                    anchors.topMargin: -16
                    anchors.bottomMargin: -16
                    // Undecided until the finger passes the drag threshold:
                    // sideways locks the slider against the shade's Flickable
                    // and dismiss drag, vertical leaves the gesture to them.
                    property bool dragging: false
                    property real pressX: 0
                    property real pressY: 0
                    preventStealing: dragging
                    // Continuous haptic on every value-step. iOS pulses
                    // at every integer crossing on the Control Center
                    // slider — same idea: gives the dragged track a
                    // physical "click" cadence.
                    property int _lastHapticStep: -1
                    onPressed: {
                        _lastHapticStep = -1;
                        dragging = false;
                        pressX = mouseX;
                        pressY = mouseY;
                    }
                    onReleased: {
                        if (!dragging)
                            applyDragAt(mouseX);
                        dragging = false;
                        // Release haptic = settle confirmation.
                        MHaptics.light();
                    }
                    onCanceled: dragging = false
                    onPositionChanged: {
                        if (!pressed)
                            return;
                        if (!dragging) {
                            const dx = Math.abs(mouseX - pressX);
                            if (dx < Qt.styleHints.startDragDistance || dx <= Math.abs(mouseY - pressY))
                                return;
                            dragging = true;
                        }
                        applyDragAt(mouseX);
                    }
                    // Not drag(): that is MouseArea's own grouped property.
                    function applyDragAt(x) {
                        const f = Math.max(0, Math.min(1, x / track.width));
                        // Whole values: the stores take an int, which would truncate.
                        root.value = Math.round(root.from + f * (root.to - root.from));
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
            color: Silica.Theme.secondaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeSmall
            font.features: ({
                    "tnum": 1
                })
        }
    }
}
