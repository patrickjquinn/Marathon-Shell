import QtQuick
import MarathonUI.Theme

Row {
    id: root

    property int count: 0
    property int currentIndex: 0
    property color activeColor: MColors.marathonTeal
    property color inactiveColor: Qt.rgba(1, 1, 1, 0.3)
    property int dotSize: 8
    property int dotSpacing: 12

    spacing: dotSpacing

    Repeater {
        model: root.count

        Rectangle {
            width: index === root.currentIndex ? dotSize * 2 : dotSize
            height: dotSize
            radius: dotSize / 2
            color: index === root.currentIndex ? root.activeColor : root.inactiveColor

            Behavior on width {
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

            // Inner highlight on active dot
            Rectangle {
                visible: index === root.currentIndex
                anchors.centerIn: parent
                width: parent.width - 2
                height: parent.height - 2
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.3)
            }
        }
    }
}
