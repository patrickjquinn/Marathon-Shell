import QtQuick
import MarathonUI.Theme
import MarathonUI.Effects
import MarathonOS.Shell

Rectangle {
    id: root

    default property alias content: contentItem.data
    property int elevation: 1
    property bool interactive: false
    property bool pressed: false

    signal clicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real shadowMargin1: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real shadowMargin2: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real shadowMargin3: Math.max(1, Math.round(3 * scaleFactor))
    readonly property real shadowMargin4: Math.max(1, Math.round(4 * scaleFactor))

    implicitWidth: parent ? parent.width : 300
    implicitHeight: contentItem.childrenRect.height + MSpacing.md * 2

    radius: MRadius.md
    color: MElevation.getSurface(elevation)
    border.width: borderWidth
    border.color: MElevation.getBorderOuter(elevation)

    scale: pressed && interactive ? 0.96 : 1.0

    Rectangle {
        id: shadowLayer
        anchors.fill: parent
        anchors.topMargin: shadowMargin3
        anchors.leftMargin: -shadowMargin1
        anchors.rightMargin: -shadowMargin1
        anchors.bottomMargin: -shadowMargin4
        z: -1
        radius: root.radius
        opacity: 0.4
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 0.2
                color: Qt.rgba(0, 0, 0, 0.3)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(0, 0, 0, 0.6)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: shadowMargin1
        anchors.bottomMargin: -shadowMargin1
        z: -2
        radius: root.radius
        color: Qt.rgba(0, 0, 0, 0.8)
        opacity: 0.3
    }

    Behavior on color {
        ColorAnimation {
            duration: MMotion.quick
        }
    }

    Behavior on scale {
        SpringAnimation {
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilon
        }
    }

    // Inner highlight — DS prescribes an asymmetric "lit from above"
    // edge treatment: a single 1 px bright stroke on the TOP edge of the
    // card, not a full 4-sided ring. Matches the m-card CSS spec
    // `inset 0 1px 0 var(--w-06)` and lines up with how buttons, keys,
    // and toggles all share the same "highlight on top, shadow on
    // bottom" reading from the reference shots.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: shadowMargin1
        anchors.rightMargin: shadowMargin1
        anchors.topMargin: shadowMargin1
        height: borderWidth
        color: MElevation.getBorderInner(elevation)
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: MSpacing.md
    }

    MRipple {
        id: ripple
    }

    MouseArea {
        anchors.fill: parent
        enabled: interactive

        onPressed: function (mouse) {
            if (interactive) {
                root.pressed = true;
                ripple.trigger(Qt.point(mouse.x, mouse.y));
            }
        }
        onReleased: root.pressed = false
        onCanceled: root.pressed = false
        onClicked: if (interactive)
            root.clicked()
    }
}
