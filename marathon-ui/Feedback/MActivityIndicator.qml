import QtQuick
import QtQuick.Shapes
import MarathonUI.Theme

Item {
    id: root

    property color color: MColors.marathonTeal
    property int size: 32
    property bool running: true

    implicitWidth: size
    implicitHeight: size

    // Modern arc-based spinner with gradient trail
    Shape {
        id: spinner
        anchors.centerIn: parent
        width: root.size
        height: root.size

        // Main spinning arc with gradient
        ShapePath {
            strokeColor: "transparent"
            fillColor: "transparent"
            strokeWidth: root.size / 8
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: spinner.width / 2
                centerY: spinner.height / 2
                radiusX: (root.size - root.size / 8) / 2
                radiusY: (root.size - root.size / 8) / 2
                startAngle: 0
                sweepAngle: 300
            }
        }

        // Gradient overlay using multiple arcs with decreasing opacity
        Repeater {
            model: 8

            Shape {
                anchors.fill: parent
                visible: root.running

                ShapePath {
                    strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, (1.0 - index / 8.0) * 0.8)
                    fillColor: "transparent"
                    strokeWidth: root.size / 8
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: spinner.width / 2
                        centerY: spinner.height / 2
                        radiusX: (root.size - root.size / 8) / 2
                        radiusY: (root.size - root.size / 8) / 2
                        startAngle: -45 * index
                        sweepAngle: 45
                    }
                }
            }
        }

        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
            running: root.running
            easing.type: Easing.Linear
        }

        opacity: root.running ? 1.0 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
            }
        }
    }
}
