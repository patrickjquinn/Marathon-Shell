import QtQuick
import Sailfish.Silica 1.0 as Silica

// The screen's edges in the ambience's highlight colour while Shipwright
// Pilot comes up (a cold start takes a second or more): lit by light(),
// fading once Pilot's overlay shows (overlayShown()) or after three seconds.
Item {
    id: root

    readonly property real band: Silica.Theme.paddingLarge * 2
    property bool lit: false

    function light() {
        lit = true;
        fadeLater.interval = 3000;
        fadeLater.restart();
    }

    function overlayShown() {
        if (!lit)
            return;
        fadeLater.interval = 400;
        fadeLater.restart();
    }

    enabled: false
    opacity: lit ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 320
            easing.type: Easing.InOutSine
        }
    }

    Timer {
        id: fadeLater

        onTriggered: root.lit = false
    }

    // A band fading in from its edge; `inward`: the edge is at the gradient start.
    component Band: Rectangle {
        id: band

        property bool inward: true
        property int orientation: Gradient.Vertical

        gradient: Gradient {
            orientation: band.orientation
            GradientStop {
                position: band.inward ? 0.0 : 1.0
                color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.5)
            }
            GradientStop {
                position: band.inward ? 0.2 : 0.8
                color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.22)
            }
            GradientStop {
                position: band.inward ? 0.55 : 0.45
                color: Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, 0.08)
            }
            GradientStop {
                position: band.inward ? 1.0 : 0.0
                color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0)
            }
        }
    }

    Band {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.band
    }

    Band {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.band
        inward: false
    }

    Band {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: root.band
        orientation: Gradient.Horizontal
    }

    Band {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.band
        orientation: Gradient.Horizontal
        inward: false
    }
}
