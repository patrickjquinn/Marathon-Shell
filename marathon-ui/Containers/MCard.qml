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

    scale: pressed && interactive ? 0.96 : 1.0  // Press only, no hover

    // Performant shadow using layered rectangles
    Rectangle {
        id: shadowLayer
        anchors.fill: parent
        anchors.topMargin: shadowMargin3
        anchors.leftMargin: -shadowMargin1
        anchors.rightMargin: -shadowMargin1
        anchors.bottomMargin: -shadowMargin4
        z: -1
        radius: parent.radius
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

    // Additional crisp shadow layer for more depth
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: shadowMargin1
        anchors.bottomMargin: -shadowMargin1
        z: -2
        radius: parent.radius
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

    // Inner highlight border
    Rectangle {
        anchors.fill: parent
        anchors.margins: shadowMargin1
        radius: parent.radius > shadowMargin1 ? parent.radius - shadowMargin1 : 0
        color: "transparent"
        border.width: borderWidth
        border.color: MElevation.getBorderInner(elevation)
    }

    // Secondary inner border for extra depth
    Rectangle {
        anchors.fill: parent
        anchors.margins: shadowMargin2
        radius: parent.radius > shadowMargin2 ? parent.radius - shadowMargin2 : 0
        color: "transparent"
        border.width: borderWidth
        border.color: Qt.rgba(1, 1, 1, 0.02)
        opacity: elevation >= 2 ? 1 : 0
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
