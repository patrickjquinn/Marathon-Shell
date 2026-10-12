import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Item {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property real value: 0.5
    property real from: 0.0
    property real to: 1.0
    property bool indeterminate: false
    property color color: MColors.marathonTeal

    implicitWidth: parent ? parent.width : 240
    implicitHeight: Math.round(4 * scaleFactor)
    clip: indeterminate

    Accessible.role: Accessible.ProgressBar
    Accessible.name: indeterminate ? "Loading" : Math.round((value - from) / (to - from) * 100) + "%"

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: MColors.bb10Surface
        border.width: 1
        border.color: MColors.borderGlass
    }

    Rectangle {
        id: fill
        height: parent.height
        width: root.indeterminate ? parent.width * 0.3 : (root.value - root.from) / (root.to - root.from) * parent.width
        radius: height / 2
        color: root.color

        x: root.indeterminate ? indeterminateAnimation.value : 0

        Behavior on width {
            enabled: !root.indeterminate
            NumberAnimation {
                duration: MMotion.quick
            }
        }
    }

    SequentialAnimation {
        id: indeterminateAnimation
        running: root.indeterminate && root.visible
        loops: Animation.Infinite

        property real value: 0

        NumberAnimation {
            target: indeterminateAnimation
            property: "value"
            from: -root.width * 0.3
            to: root.width
            duration: 1500
            easing.type: Easing.InOutCubic
        }
    }
}
