import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings slider: a glass pill the ambience tint fills as the value
// rises, its glyph at the left end and the value at the right. The whole
// pill is the control; there is no thumb.
Item {
    id: root

    property string iconName: "brightness"
    property real value: 50          // 0..100
    property real from: 0
    property real to: 100
    property string a11yName: ""

    signal moved(real value)

    implicitHeight: Silica.Theme.itemSizeExtraSmall + Silica.Theme.paddingSmall

    Accessible.role: Accessible.Slider
    Accessible.name: a11yName

    readonly property real fraction: (value - from) / Math.max(1, to - from)

    Silica.GlassSurface {
        id: track

        objectName: "sliderTrack"
        anchors.fill: parent
        anchors.topMargin: Silica.Theme.paddingSmall / 2
        anchors.bottomMargin: Silica.Theme.paddingSmall / 2
        radius: height / 2
        pressed: trackHit.pressed

        Rectangle {
            width: Math.max(parent.height, parent.width * root.fraction)
            height: parent.height
            radius: parent.radius
            color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.38)
        }

        GlyphIcon {
            x: Silica.Theme.paddingLarge
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: Silica.Theme.iconSizeSmall
            color: Silica.Theme.primaryColor
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Silica.Theme.paddingLarge
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.value)
            color: Silica.Theme.secondaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeSmall
            font.features: ({
                    "tnum": 1
                })
        }
    }

    MouseArea {
        id: trackHit
        // The whole pill, and at least the 7 mm minimum.
        anchors.fill: track
        anchors.topMargin: -Math.max(0, (Constants.touchTargetMinimum - track.height) / 2)
        anchors.bottomMargin: anchors.topMargin
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
                if (dx < Application.styleHints.startDragDistance || dx <= Math.abs(mouseY - pressY))
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
